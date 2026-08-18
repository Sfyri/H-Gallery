from __future__ import annotations

import atexit
import hashlib
import json
import secrets
import socket
import threading
import time
from pathlib import Path
from typing import Any

from backend.app_config import get_user_config_root
from backend.paths import GALLERY_NAME
from backend.version import get_display_version

DISCOVERY_PORT = 47851
DEFAULT_API_PORT = 8000
PROTOCOL = "h-gallery-m6"
PAIRING_TTL_SECONDS = 300


class MobileLinkService:
    def __init__(self) -> None:
        self._lock = threading.RLock()
        self._stop_event = threading.Event()
        self._thread: threading.Thread | None = None
        self._socket: socket.socket | None = None
        self._api_port = DEFAULT_API_PORT
        self._pairing_code = ""
        self._pairing_expires_at = 0.0
        self._state_path: Path = get_user_config_root() / "mobile_devices.json"
        self._devices: dict[str, dict[str, Any]] = self._load_devices()

    def _load_devices(self) -> dict[str, dict[str, Any]]:
        try:
            raw = json.loads(self._state_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return {}
        devices = raw.get("devices", {}) if isinstance(raw, dict) else {}
        return devices if isinstance(devices, dict) else {}

    def _save_devices(self) -> None:
        self._state_path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self._state_path.with_suffix(".tmp")
        temporary.write_text(
            json.dumps({"devices": self._devices}, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        temporary.replace(self._state_path)

    def _ensure_pairing_code(self) -> None:
        now = time.time()
        if self._pairing_code and now < self._pairing_expires_at:
            return
        self._pairing_code = f"{secrets.randbelow(900000) + 100000:06d}"
        self._pairing_expires_at = now + PAIRING_TTL_SECONDS

    def start(self, *, api_port: int = DEFAULT_API_PORT) -> None:
        with self._lock:
            self._api_port = int(api_port)
            self._ensure_pairing_code()
            if self._thread and self._thread.is_alive():
                return
            self._stop_event.clear()
            self._thread = threading.Thread(
                target=self._discovery_loop,
                name="h-gallery-mobile-discovery",
                daemon=True,
            )
            self._thread.start()

    def stop(self) -> None:
        self._stop_event.set()
        with self._lock:
            sock = self._socket
            self._socket = None
        if sock is not None:
            try:
                sock.close()
            except OSError:
                pass

    def _discovery_loop(self) -> None:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.settimeout(0.5)
        try:
            sock.bind(("0.0.0.0", DISCOVERY_PORT))
        except OSError:
            sock.close()
            return
        with self._lock:
            self._socket = sock
        try:
            while not self._stop_event.is_set():
                try:
                    payload, address = sock.recvfrom(4096)
                except socket.timeout:
                    continue
                except OSError:
                    break
                try:
                    request = json.loads(payload.decode("utf-8"))
                except (UnicodeDecodeError, json.JSONDecodeError):
                    continue
                if not isinstance(request, dict):
                    continue
                if request.get("protocol") != PROTOCOL or request.get("action") != "discover":
                    continue
                response = {
                    "protocol": PROTOCOL,
                    "action": "offer",
                    "name": socket.gethostname(),
                    "gallery": GALLERY_NAME,
                    "version": get_display_version(),
                    "port": self._api_port,
                }
                try:
                    sock.sendto(json.dumps(response).encode("utf-8"), address)
                except OSError:
                    continue
        finally:
            with self._lock:
                if self._socket is sock:
                    self._socket = None
            try:
                sock.close()
            except OSError:
                pass

    def hello(self) -> dict[str, Any]:
        return {
            "protocol": PROTOCOL,
            "device_name": socket.gethostname(),
            "gallery_name": GALLERY_NAME,
            "version": get_display_version(),
            "pairing_required": True,
        }

    def pairing_status(self) -> dict[str, Any]:
        with self._lock:
            self._ensure_pairing_code()
            devices = [
                {
                    "device_id": device_id,
                    "name": data.get("name", "Android"),
                    "paired_at": data.get("paired_at"),
                    "last_seen": data.get("last_seen"),
                }
                for device_id, data in self._devices.items()
            ]
            devices.sort(key=lambda item: str(item.get("name", "")).lower())
            return {
                "code": self._pairing_code,
                "expires_at": self._pairing_expires_at,
                "devices": devices,
                "discovery_port": DISCOVERY_PORT,
                "api_port": self._api_port,
            }

    def refresh_pairing_code(self) -> dict[str, Any]:
        with self._lock:
            self._pairing_code = ""
            self._pairing_expires_at = 0.0
            self._ensure_pairing_code()
        return self.pairing_status()

    def pair(self, *, device_id: str, name: str, code: str) -> dict[str, Any]:
        device_id = device_id.strip()
        name = name.strip() or "Android"
        code = code.strip()
        if not device_id or len(device_id) > 160:
            raise ValueError("Identificativo dispositivo non valido.")
        if len(name) > 120:
            raise ValueError("Nome dispositivo troppo lungo.")
        with self._lock:
            self._ensure_pairing_code()
            if time.time() >= self._pairing_expires_at or not secrets.compare_digest(code, self._pairing_code):
                raise ValueError("Codice di associazione non valido o scaduto.")
            token = secrets.token_urlsafe(32)
            now = time.time()
            self._devices[device_id] = {
                "name": name,
                "token_hash": hashlib.sha256(token.encode("utf-8")).hexdigest(),
                "paired_at": now,
                "last_seen": now,
            }
            self._save_devices()
            self._pairing_code = ""
            self._pairing_expires_at = 0.0
            self._ensure_pairing_code()
            return {
                "status": "paired",
                "token": token,
                "device_name": socket.gethostname(),
                "gallery_name": GALLERY_NAME,
                "version": get_display_version(),
            }

    def status(self, *, device_id: str, token: str) -> dict[str, Any]:
        with self._lock:
            data = self._devices.get(device_id)
            if not data:
                raise PermissionError("Dispositivo non associato.")
            received_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
            expected_hash = str(data.get("token_hash", ""))
            if not expected_hash or not secrets.compare_digest(received_hash, expected_hash):
                raise PermissionError("Token dispositivo non valido.")
            data["last_seen"] = time.time()
            self._save_devices()
            return {
                "status": "connected",
                "device_name": socket.gethostname(),
                "gallery_name": GALLERY_NAME,
                "version": get_display_version(),
            }

    def forget(self, device_id: str) -> bool:
        with self._lock:
            removed = self._devices.pop(device_id, None) is not None
            if removed:
                self._save_devices()
            return removed


MOBILE_LINK_SERVICE = MobileLinkService()
atexit.register(MOBILE_LINK_SERVICE.stop)

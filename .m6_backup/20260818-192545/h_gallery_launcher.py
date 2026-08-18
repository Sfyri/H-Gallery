from __future__ import annotations

import argparse
import json
import logging
import os
import socket
import subprocess
import sys
import threading
import time
import webbrowser
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Any, Sequence

from backend.app_config import get_active_gallery, get_user_cache_root, get_user_config_root
from backend.version import get_display_version
from configure import ensure_configuration

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8000
CONTROL_STATE_PATH = get_user_config_root() / "launcher.json"
CONTROL_LOCK_PATH = get_user_config_root() / "launcher.lock"
LOG_ROOT = get_user_cache_root().parent / "logs"
LOG_PATH = LOG_ROOT / "h-gallery.log"

_CREATE_NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)
_DETACHED_PROCESS = getattr(subprocess, "DETACHED_PROCESS", 0)
_CREATE_NEW_PROCESS_GROUP = getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)


def _atomic_write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)


def _read_control_state() -> dict[str, Any] | None:
    try:
        data = json.loads(CONTROL_STATE_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(data, dict):
        return None
    try:
        port = int(data.get("port"))
    except (TypeError, ValueError):
        return None
    if not 1 <= port <= 65535:
        return None
    return data


def send_launcher_command(command: str, *, timeout: float = 1.2) -> str | None:
    """Invia un comando a un launcher già attivo.

    Restituisce la risposta del launcher oppure ``None`` quando l'istanza non
    è raggiungibile.
    """

    state = _read_control_state()
    if state is None:
        return None
    try:
        with socket.create_connection(("127.0.0.1", int(state["port"])), timeout=timeout) as connection:
            connection.sendall((command.strip().upper() + "\n").encode("utf-8"))
            connection.settimeout(timeout)
            response = connection.recv(4096).decode("utf-8", errors="replace").strip()
            return response or "OK"
    except OSError:
        return None



def _pid_is_running(pid: int) -> bool:
    if pid <= 0:
        return False
    if os.name == "nt":
        try:
            import ctypes

            process_query_limited_information = 0x1000
            handle = ctypes.windll.kernel32.OpenProcess(
                process_query_limited_information,
                False,
                pid,
            )
            if not handle:
                return False
            ctypes.windll.kernel32.CloseHandle(handle)
            return True
        except Exception:
            return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False
    return True


def _read_lock_pid() -> int | None:
    try:
        value = CONTROL_LOCK_PATH.read_text(encoding="ascii").strip()
        return int(value)
    except (OSError, ValueError):
        return None

def _pythonw_executable() -> Path:
    executable = Path(sys.executable)
    if os.name == "nt":
        candidate = executable.with_name("pythonw.exe")
        if candidate.is_file():
            return candidate
    return executable


def _is_frozen_application() -> bool:
    return bool(getattr(sys, "frozen", False))


def _launcher_command(*arguments: str) -> list[str]:
    """Costruisce il comando corretto per sorgente, pip e bundle PyInstaller."""

    if _is_frozen_application():
        return [str(Path(sys.executable)), *arguments]
    return [str(_pythonw_executable()), "-m", "h_gallery_launcher", *arguments]


def launch_detached() -> int:
    """Avvia il launcher in background e restituisce subito il controllo."""

    if send_launcher_command("OPEN") is not None:
        return 0

    command = _launcher_command("--foreground")
    kwargs: dict[str, Any] = {
        "close_fds": True,
        "stdin": subprocess.DEVNULL,
        "stdout": subprocess.DEVNULL,
        "stderr": subprocess.DEVNULL,
    }
    if os.name == "nt":
        kwargs["creationflags"] = (
            _CREATE_NO_WINDOW | _DETACHED_PROCESS | _CREATE_NEW_PROCESS_GROUP
        )
    else:
        kwargs["start_new_session"] = True

    try:
        subprocess.Popen(command, **kwargs)
    except OSError as error:
        print(f"Impossibile avviare H-Gallery in background: {error}", file=sys.stderr)
        return 1
    return 0


def _show_windows_message(title: str, message: str, *, error: bool = False) -> None:
    if os.name == "nt":
        try:
            import ctypes

            flags = 0x00000000 | (0x00000010 if error else 0x00000040)
            ctypes.windll.user32.MessageBoxW(None, message, title, flags)
            return
        except Exception:
            pass
    try:
        import tkinter as tk
        from tkinter import messagebox

        root = tk.Tk()
        root.withdraw()
        if error:
            messagebox.showerror(title, message, parent=root)
        else:
            messagebox.showinfo(title, message, parent=root)
        root.destroy()
    except Exception:
        logging.getLogger(__name__).error("%s: %s", title, message)


def _open_path(path: Path) -> None:
    if os.name == "nt":
        os.startfile(str(path))  # type: ignore[attr-defined]
        return
    if sys.platform == "darwin":
        subprocess.Popen(["open", str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return
    subprocess.Popen(["xdg-open", str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def _browser_url(host: str, port: int) -> str:
    browser_host = "127.0.0.1" if host in {"0.0.0.0", "::", "localhost"} else host
    return f"http://{browser_host}:{port}"


def _configure_logging() -> None:
    LOG_ROOT.mkdir(parents=True, exist_ok=True)
    handler = RotatingFileHandler(
        LOG_PATH,
        maxBytes=2_000_000,
        backupCount=3,
        encoding="utf-8",
    )
    handler.setFormatter(
        logging.Formatter("%(asctime)s | %(levelname)s | %(name)s | %(message)s")
    )
    root = logging.getLogger()
    root.setLevel(logging.INFO)
    root.handlers.clear()
    root.addHandler(handler)
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        logger = logging.getLogger(name)
        logger.handlers.clear()
        logger.propagate = True


class LauncherAlreadyRunning(RuntimeError):
    pass


class LauncherApp:
    def __init__(self, *, host: str = DEFAULT_HOST, port: int = DEFAULT_PORT) -> None:
        self.host = host
        self.port = port
        self.url = _browser_url(host, port)
        self.gallery: dict[str, Any] | None = None
        self.icon: Any = None
        self.server: Any = None
        self.server_thread: threading.Thread | None = None
        self.control_socket: socket.socket | None = None
        self.control_thread: threading.Thread | None = None
        self.lock_fd: int | None = None
        self.stop_event = threading.Event()
        self.server_ready = threading.Event()
        self.restart_requested = False
        self.reconfigure_in_progress = False
        self.exit_code = 0

    def _acquire_instance_lock(self) -> None:
        CONTROL_LOCK_PATH.parent.mkdir(parents=True, exist_ok=True)
        for _attempt in range(2):
            try:
                self.lock_fd = os.open(
                    CONTROL_LOCK_PATH,
                    os.O_CREAT | os.O_EXCL | os.O_WRONLY,
                )
                os.write(self.lock_fd, str(os.getpid()).encode("ascii"))
                return
            except FileExistsError:
                for _ in range(20):
                    if send_launcher_command("OPEN", timeout=0.25) is not None:
                        raise LauncherAlreadyRunning
                    time.sleep(0.1)
                # Durante la prima configurazione il launcher può avere già
                # acquisito il lock ma non avere ancora aperto la porta di
                # controllo. In quel caso non deve essere considerato stale.
                existing_pid = _read_lock_pid()
                if existing_pid is not None and _pid_is_running(existing_pid):
                    raise LauncherAlreadyRunning
                # Il processo non esiste più: il lock è un residuo di un
                # arresto anomalo e può essere rimosso.
                try:
                    CONTROL_LOCK_PATH.unlink()
                except OSError:
                    pass
                try:
                    CONTROL_STATE_PATH.unlink()
                except OSError:
                    pass
        raise RuntimeError("Impossibile acquisire il controllo del launcher.")

    def _start_control_server(self) -> None:
        control = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        control.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        control.bind(("127.0.0.1", 0))
        control.listen(5)
        control.settimeout(0.5)
        self.control_socket = control
        port = int(control.getsockname()[1])
        _atomic_write_json(
            CONTROL_STATE_PATH,
            {
                "pid": os.getpid(),
                "port": port,
                "url": self.url,
                "version": get_display_version(),
                "started_at": time.time(),
            },
        )
        self.control_thread = threading.Thread(
            target=self._control_loop,
            name="h-gallery-control",
            daemon=True,
        )
        self.control_thread.start()

    def _control_loop(self) -> None:
        while not self.stop_event.is_set():
            try:
                assert self.control_socket is not None
                connection, _address = self.control_socket.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            with connection:
                try:
                    command = connection.recv(256).decode("utf-8", errors="replace").strip().upper()
                    response = self._handle_control_command(command)
                    connection.sendall((response + "\n").encode("utf-8"))
                except OSError:
                    continue

    def _handle_control_command(self, command: str) -> str:
        if command == "OPEN":
            self.open_browser()
            return "OK OPEN"
        if command == "STOP":
            threading.Thread(target=self.request_stop, daemon=True).start()
            return "OK STOP"
        if command == "FOLDER":
            threading.Thread(target=self.open_gallery_folder, daemon=True).start()
            return "OK FOLDER"
        if command == "STATUS":
            state = "ready" if self.server_ready.is_set() else "starting"
            return f"OK {state} {self.url}"
        return "ERROR UNKNOWN_COMMAND"

    def _port_is_available(self) -> bool:
        probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            probe.bind((self.host, self.port))
            return True
        except OSError:
            return False
        finally:
            probe.close()

    def _start_server(self) -> None:
        if not self._port_is_available():
            raise RuntimeError(
                f"La porta {self.port} è già occupata. Chiudi l'altro server "
                "oppure arresta la precedente istanza di H-Gallery."
            )

        # I percorsi della galleria vengono risolti quando `main` viene
        # importato: la configurazione deve quindi essere già pronta.
        import uvicorn
        from main import app

        config = uvicorn.Config(
            app,
            host=self.host,
            port=self.port,
            log_config=None,
            access_log=False,
            server_header=False,
        )
        self.server = uvicorn.Server(config)
        self.server_thread = threading.Thread(
            target=self._server_worker,
            name="h-gallery-server",
            daemon=True,
        )
        self.server_thread.start()

        threading.Thread(
            target=self._monitor_server_startup,
            name="h-gallery-startup-monitor",
            daemon=True,
        ).start()

    def _server_worker(self) -> None:
        try:
            assert self.server is not None
            self.server.run()
        except Exception:
            logging.getLogger(__name__).exception("Errore non gestito nel server")
        finally:
            if not self.stop_event.is_set() and not self.server_ready.is_set():
                self.exit_code = 1

    def _monitor_server_startup(self) -> None:
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline and not self.stop_event.is_set():
            if self.server is not None and bool(getattr(self.server, "started", False)):
                self.server_ready.set()
                self.open_browser()
                try:
                    if self.icon is not None:
                        self.icon.notify(
                            f"Galleria attiva: {self.gallery['name']}",
                            "H-Gallery è pronta",
                        )
                except Exception:
                    pass
                return
            if self.server_thread is not None and not self.server_thread.is_alive():
                break
            time.sleep(0.15)

        if not self.stop_event.is_set():
            self.exit_code = 1
            _show_windows_message(
                "H-Gallery",
                "Il server non è riuscito ad avviarsi.\n\n"
                f"Controlla il log:\n{LOG_PATH}",
                error=True,
            )
            self.request_stop()

    def _create_icon_image(self):
        from PIL import Image, ImageDraw

        size = 64
        image = Image.new("RGBA", (size, size), (34, 39, 54, 255))
        draw = ImageDraw.Draw(image)
        draw.rounded_rectangle((4, 4, 59, 59), radius=12, fill=(103, 80, 164, 255))
        draw.rectangle((17, 14, 24, 50), fill=(255, 255, 255, 255))
        draw.rectangle((40, 14, 47, 50), fill=(255, 255, 255, 255))
        draw.rectangle((23, 29, 41, 36), fill=(255, 255, 255, 255))
        return image

    def _build_tray_icon(self):
        try:
            import pystray
        except ImportError as error:
            raise RuntimeError(
                "Il componente del launcher non è installato. Esegui nuovamente Install.bat."
            ) from error

        def gallery_label(_item: Any) -> str:
            if self.gallery is None:
                return "Galleria: non configurata"
            return f"Galleria: {self.gallery['name']}"

        menu = pystray.Menu(
            pystray.MenuItem("Apri H-Gallery", self._menu_open, default=True),
            pystray.MenuItem(gallery_label, lambda _icon, _item: None, enabled=False),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Apri cartella della galleria", self._menu_open_folder),
            pystray.MenuItem("Cambia galleria...", self._menu_change_gallery),
            pystray.MenuItem("Apri cartella dei log", self._menu_open_logs),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Arresta H-Gallery", self._menu_stop),
        )
        return pystray.Icon(
            "h-gallery",
            self._create_icon_image(),
            f"H-Gallery {get_display_version()}",
            menu,
        )

    def _menu_open(self, _icon: Any = None, _item: Any = None) -> None:
        self.open_browser()

    def _menu_open_folder(self, _icon: Any = None, _item: Any = None) -> None:
        threading.Thread(target=self.open_gallery_folder, daemon=True).start()

    def _menu_open_logs(self, _icon: Any = None, _item: Any = None) -> None:
        threading.Thread(target=lambda: _open_path(LOG_ROOT), daemon=True).start()

    def _menu_change_gallery(self, _icon: Any = None, _item: Any = None) -> None:
        if self.reconfigure_in_progress:
            return
        self.reconfigure_in_progress = True
        threading.Thread(target=self._change_gallery_worker, daemon=True).start()

    def _menu_stop(self, _icon: Any = None, _item: Any = None) -> None:
        self.request_stop()

    def open_browser(self) -> None:
        webbrowser.open(self.url, new=2)

    def open_gallery_folder(self) -> None:
        if self.gallery is not None:
            _open_path(Path(str(self.gallery["path"])))

    def _change_gallery_worker(self) -> None:
        previous_id = str(self.gallery.get("id")) if self.gallery else ""
        command = _launcher_command("--configure")
        kwargs: dict[str, Any] = {
            "stdin": subprocess.DEVNULL,
            "stdout": subprocess.DEVNULL,
            "stderr": subprocess.DEVNULL,
        }
        if os.name == "nt":
            kwargs["creationflags"] = _CREATE_NO_WINDOW
        try:
            completed = subprocess.run(command, **kwargs)
            if completed.returncode != 0:
                return
            current = get_active_gallery()
            if str(current.get("id")) != previous_id:
                self.restart_requested = True
                self.request_stop()
        except Exception:
            logging.getLogger(__name__).exception("Impossibile cambiare galleria")
            _show_windows_message(
                "H-Gallery",
                "Non è stato possibile aprire il gestore delle gallerie.\n\n"
                f"Controlla il log:\n{LOG_PATH}",
                error=True,
            )
        finally:
            self.reconfigure_in_progress = False

    def request_stop(self) -> None:
        if self.stop_event.is_set():
            return
        self.stop_event.set()
        if self.server is not None:
            self.server.should_exit = True
        try:
            if self.icon is not None:
                self.icon.stop()
        except Exception:
            pass

    def _cleanup(self) -> None:
        self.stop_event.set()
        if self.server is not None:
            self.server.should_exit = True
        if self.server_thread is not None:
            self.server_thread.join(timeout=10)
            if self.server_thread.is_alive() and self.server is not None:
                self.server.force_exit = True
                self.server_thread.join(timeout=2)
        if self.control_socket is not None:
            try:
                self.control_socket.close()
            except OSError:
                pass
        if self.control_thread is not None:
            self.control_thread.join(timeout=1)
        if self.lock_fd is not None:
            try:
                os.close(self.lock_fd)
            except OSError:
                pass
            self.lock_fd = None
        for path in (CONTROL_STATE_PATH, CONTROL_LOCK_PATH):
            try:
                path.unlink()
            except OSError:
                pass

    def _restart(self) -> None:
        command = _launcher_command("--foreground")
        kwargs: dict[str, Any] = {
            "close_fds": True,
            "stdin": subprocess.DEVNULL,
            "stdout": subprocess.DEVNULL,
            "stderr": subprocess.DEVNULL,
        }
        if os.name == "nt":
            kwargs["creationflags"] = (
                _CREATE_NO_WINDOW | _DETACHED_PROCESS | _CREATE_NEW_PROCESS_GROUP
            )
        else:
            kwargs["start_new_session"] = True
        subprocess.Popen(command, **kwargs)

    def run(self) -> int:
        _configure_logging()
        try:
            self._acquire_instance_lock()
        except LauncherAlreadyRunning:
            return 0

        try:
            self.gallery = ensure_configuration()
            self._start_control_server()
            self.icon = self._build_tray_icon()
            self._start_server()
            self.icon.run()
        except Exception as error:
            logging.getLogger(__name__).exception("Avvio del launcher non riuscito")
            _show_windows_message(
                "H-Gallery",
                f"H-Gallery non è riuscita ad avviarsi.\n\n{error}\n\n"
                f"Log: {LOG_PATH}",
                error=True,
            )
            self.exit_code = 1
        finally:
            self._cleanup()

        if self.restart_requested:
            try:
                self._restart()
            except OSError:
                logging.getLogger(__name__).exception("Riavvio del launcher non riuscito")
                return 1
        return self.exit_code


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="h-gallery-launcher", add_help=True)
    parser.add_argument("--foreground", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--open", action="store_true", help="apre l'istanza già attiva")
    parser.add_argument("--stop", action="store_true", help="arresta l'istanza già attiva")
    parser.add_argument("--status", action="store_true", help="mostra lo stato del launcher")
    parser.add_argument(
        "--configure",
        action="store_true",
        help="apre il gestore grafico delle gallerie",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _build_parser().parse_args(list(argv) if argv is not None else None)
    if args.open:
        return 0 if send_launcher_command("OPEN") is not None else 1
    if args.stop:
        return 0 if send_launcher_command("STOP") is not None else 1
    if args.status:
        response = send_launcher_command("STATUS")
        if response is None:
            print("H-Gallery non è in esecuzione.")
            return 1
        print(response)
        return 0
    if args.configure:
        try:
            from configure import run_gallery_manager

            run_gallery_manager(require_selection=False)
            return 0
        except Exception as error:
            logging.getLogger(__name__).exception("Gestore gallerie non riuscito")
            _show_windows_message(
                "H-Gallery",
                f"Non è stato possibile aprire il gestore delle gallerie.\n\n{error}",
                error=True,
            )
            return 1
    if not args.foreground:
        return launch_detached()
    return LauncherApp().run()


if __name__ == "__main__":
    raise SystemExit(main())

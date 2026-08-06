from __future__ import annotations

import argparse
import socket
import sys
import threading
import time
import webbrowser
from pathlib import Path
from typing import Sequence

from backend.app_config import list_galleries, register_gallery
from backend.version import get_display_version
from configure import configure_gallery, ensure_configuration, run_gallery_manager

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8000


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="h-gallery",
        description="Avvia e configura H-Gallery.",
    )
    parser.add_argument(
        "--version",
        action="version",
        version=f"H-Gallery {get_display_version()}",
    )

    subparsers = parser.add_subparsers(dest="command")

    start = subparsers.add_parser("start", help="avvia il server locale")
    start.add_argument("--gallery", type=Path, help="galleria da usare per questo avvio")
    start.add_argument("--host", default=DEFAULT_HOST, help="indirizzo del server")
    start.add_argument("--port", type=int, default=DEFAULT_PORT, help="porta del server")
    start.add_argument(
        "--no-browser",
        action="store_true",
        help="non apre automaticamente il browser",
    )

    configure = subparsers.add_parser(
        "configure",
        help="apre il gestore delle gallerie",
    )
    configure.add_argument(
        "--gallery",
        type=Path,
        help="registra e rende attiva una galleria esistente",
    )
    configure.add_argument(
        "--create",
        type=Path,
        help="crea e rende attiva una nuova galleria",
    )
    configure.add_argument(
        "--ensure",
        action="store_true",
        help="verifica la galleria attiva senza aprire il gestore se è già valida",
    )

    subparsers.add_parser("list", help="elenca le gallerie configurate")
    subparsers.add_parser("launcher", help="avvia H-Gallery in background con icona nell'area di notifica")
    subparsers.add_parser("open", help="apre nel browser il launcher già attivo")
    subparsers.add_parser("stop", help="arresta il launcher già attivo")
    subparsers.add_parser("status", help="mostra lo stato del launcher")
    return parser


def _normalize_legacy_arguments(argv: Sequence[str]) -> list[str]:
    """Permette anche `h-gallery --gallery ...` senza scrivere `start`."""

    args = list(argv)
    if not args:
        return ["start"]
    if args[0] in {"start", "configure", "list", "launcher", "open", "stop", "status", "-h", "--help", "--version"}:
        return args
    return ["start", *args]


def _select_gallery(path: Path | None) -> dict[str, str]:
    if path is None:
        return ensure_configuration()
    entry = register_gallery(path, make_active=True, create_layout=True)
    configure_gallery(entry)
    return entry


def _browser_url(host: str, port: int) -> str:
    browser_host = "127.0.0.1" if host in {"0.0.0.0", "::"} else host
    if browser_host == "localhost":
        browser_host = "127.0.0.1"
    return f"http://{browser_host}:{port}"


def _open_browser_when_ready(host: str, port: int) -> None:
    url = _browser_url(host, port)
    deadline = time.monotonic() + 15
    probe_host = "127.0.0.1" if host in {"0.0.0.0", "::", "localhost"} else host
    while time.monotonic() < deadline:
        try:
            with socket.create_connection((probe_host, port), timeout=0.4):
                webbrowser.open(url, new=2)
                return
        except OSError:
            time.sleep(0.2)


def _start_server(args: argparse.Namespace) -> int:
    if not 1 <= args.port <= 65535:
        raise ValueError("La porta deve essere compresa tra 1 e 65535.")

    entry = _select_gallery(args.gallery)

    # Questi import devono avvenire soltanto dopo la scelta della galleria:
    # backend.paths risolve i percorsi dell'archivio durante l'importazione.
    import uvicorn
    from main import app

    print(f"H-Gallery {get_display_version()}")
    print(f"Galleria attiva: {entry['name']} — {entry['path']}")
    print(f"Indirizzo: {_browser_url(args.host, args.port)}")
    print("Premi Ctrl+C per arrestare H-Gallery.\n")

    if not args.no_browser:
        threading.Thread(
            target=_open_browser_when_ready,
            args=(args.host, args.port),
            daemon=True,
        ).start()

    uvicorn.run(app, host=args.host, port=args.port, log_level="info")
    return 0


def _configure(args: argparse.Namespace) -> int:
    selected_options = sum(bool(value) for value in (args.gallery, args.create, args.ensure))
    if selected_options > 1:
        raise ValueError("Usa soltanto una tra --gallery, --create e --ensure.")
    if args.gallery:
        entry = register_gallery(args.gallery, make_active=True, create_layout=True)
        configure_gallery(entry)
    elif args.create:
        entry = register_gallery(args.create, make_active=True, create_layout=True)
        configure_gallery(entry)
    elif args.ensure:
        entry = ensure_configuration()
    else:
        entry = run_gallery_manager(require_selection=False)
        if entry is None:
            return 0
    print(f"Galleria attiva: {entry['name']} — {entry['path']}")
    return 0


def _list() -> int:
    data = list_galleries()
    results = data.get("results", [])
    if not results:
        print("Nessuna galleria configurata.")
        return 0
    for item in results:
        marker = "*" if item.get("active") else " "
        status = "disponibile" if item.get("available") else "non disponibile"
        print(f"{marker} {item['name']} — {item['path']} ({status})")
    return 0


def _launcher_command(command: str) -> int:
    from h_gallery_launcher import launch_detached, send_launcher_command

    if command == "launcher":
        return launch_detached()
    response = send_launcher_command(command.upper())
    if response is None:
        if command == "status":
            print("H-Gallery non è in esecuzione.")
        else:
            print("Nessuna istanza del launcher è in esecuzione.", file=sys.stderr)
        return 1
    if command == "status":
        print(response)
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    parser = _build_parser()
    raw_args = sys.argv[1:] if argv is None else list(argv)
    parsed = parser.parse_args(_normalize_legacy_arguments(raw_args))
    try:
        if parsed.command == "configure":
            return _configure(parsed)
        if parsed.command == "list":
            return _list()
        if parsed.command in {"launcher", "open", "stop", "status"}:
            return _launcher_command(parsed.command)
        return _start_server(parsed)
    except KeyboardInterrupt:
        return 0
    except (OSError, RuntimeError, ValueError) as error:
        print(f"Errore: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

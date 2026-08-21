from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path
from typing import Any, Sequence

import h_gallery_launcher as base


send_launcher_command = base.send_launcher_command


def _launcher_command(*arguments: str) -> list[str]:
    if base._is_frozen_application():
        return [str(Path(sys.executable)), *arguments]
    return [str(base._pythonw_executable()), "-m", "h_gallery_mobile_launcher", *arguments]


def launch_detached() -> int:
    if base.send_launcher_command("OPEN") is not None:
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
            base._CREATE_NO_WINDOW | base._DETACHED_PROCESS | base._CREATE_NEW_PROCESS_GROUP
        )
    else:
        kwargs["start_new_session"] = True
    try:
        subprocess.Popen(command, **kwargs)
    except OSError as error:
        print(f"Impossibile avviare H-Gallery in background: {error}", file=sys.stderr)
        return 1
    return 0


class MobileLauncherApp(base.LauncherApp):
    def _start_server(self) -> None:
        if not self._port_is_available():
            raise RuntimeError(
                f"La porta {self.port} è già occupata. Chiudi l'altro server "
                "oppure arresta la precedente istanza di H-Gallery."
            )

        import uvicorn
        from main_android import app

        config = uvicorn.Config(
            app,
            host=self.host,
            port=self.port,
            log_config=None,
            access_log=False,
            server_header=False,
        )
        self.server = uvicorn.Server(config)
        self.server_thread = base.threading.Thread(
            target=self._server_worker,
            name="h-gallery-server",
            daemon=True,
        )
        self.server_thread.start()
        base.threading.Thread(
            target=self._monitor_server_startup,
            name="h-gallery-startup-monitor",
            daemon=True,
        ).start()

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
                base._CREATE_NO_WINDOW | base._DETACHED_PROCESS | base._CREATE_NEW_PROCESS_GROUP
            )
        else:
            kwargs["start_new_session"] = True
        subprocess.Popen(command, **kwargs)


def main(argv: Sequence[str] | None = None) -> int:
    args = base._build_parser().parse_args(list(argv) if argv is not None else None)
    if args.open:
        return 0 if base.send_launcher_command("OPEN") is not None else 1
    if args.stop:
        return 0 if base.send_launcher_command("STOP") is not None else 1
    if args.status:
        response = base.send_launcher_command("STATUS")
        if response is None:
            print("H-Gallery non è in esecuzione.")
            return 1
        print(response)
        return 0
    if args.configure:
        return base.main(["--configure"])
    if not args.foreground:
        return launch_detached()
    return MobileLauncherApp().run()


if __name__ == "__main__":
    raise SystemExit(main())

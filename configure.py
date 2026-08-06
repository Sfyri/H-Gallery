from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path
from typing import Any

from backend.app_config import (
    REGISTRY_PATH,
    get_active_gallery,
    list_galleries,
    load_registry,
    register_gallery,
    remove_gallery,
    set_active_gallery,
)
from backend.resources import CONFIG_EXAMPLE_PATH

SCRIPT_ROOT = Path(__file__).resolve().parent
EXAMPLE_CONFIG_PATH = CONFIG_EXAMPLE_PATH
LEGACY_CONFIG_PATH = SCRIPT_ROOT / "config.json"


def _read_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise FileNotFoundError(f"File di configurazione non trovato: {path}")
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"{path.name} non contiene un oggetto JSON valido.")
    return data


def _write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)




def _merge_legacy_directory(source: Path, destination: Path) -> bool:
    if not source.is_dir():
        return False
    destination.mkdir(parents=True, exist_ok=True)
    for child in list(source.iterdir()):
        target = destination / child.name
        if target.exists():
            # Non sovrascrive mai dati già presenti nella galleria.
            continue
        shutil.move(str(child), str(target))
    try:
        source.rmdir()
    except OSError:
        pass
    return True


def _migrate_legacy_storage(gallery_root: Path) -> None:
    # La migrazione 1.x è pertinente solo quando .Script si trova ancora
    # direttamente dentro la galleria selezionata.
    if SCRIPT_ROOT.parent.resolve() != gallery_root.resolve():
        return
    _merge_legacy_directory(SCRIPT_ROOT / "data", gallery_root / ".user" / "data")
    _merge_legacy_directory(SCRIPT_ROOT / "backups", gallery_root / ".user" / "backups")


def configure_gallery(entry: dict[str, Any]) -> Path:
    """Prepara cartelle e preferenze della galleria selezionata."""

    gallery_root = Path(str(entry["path"])).resolve()
    user_root = gallery_root / ".user"
    config_path = user_root / "config.json"
    defaults = _read_json(EXAMPLE_CONFIG_PATH)

    current: dict[str, Any] = {}
    if config_path.exists():
        current = _read_json(config_path)
    elif (
        LEGACY_CONFIG_PATH.exists()
        and SCRIPT_ROOT.parent.resolve() == gallery_root.resolve()
    ):
        # Copia non distruttiva della configurazione 1.x soltanto quando il
        # programma si trova ancora dentro quella stessa galleria.
        current = _read_json(LEGACY_CONFIG_PATH)

    config = {**defaults, **current}
    config.pop("gallery_root", None)
    config.pop("script_folder", None)

    for relative in (".user/data", ".user/backups"):
        (gallery_root / relative).mkdir(parents=True, exist_ok=True)

    todo_folder = str(config.get("todo_folder", ".toDo"))
    trash_folder = str(config.get("trash_folder", ".trash"))
    for folder_name in (todo_folder, trash_folder):
        (gallery_root / folder_name).mkdir(parents=True, exist_ok=True)

    _write_json(config_path, config)
    _migrate_legacy_storage(gallery_root)
    return config_path


def _active_or_none() -> dict[str, Any] | None:
    try:
        return get_active_gallery(script_root=SCRIPT_ROOT)
    except (RuntimeError, NotADirectoryError):
        return None


def ensure_configuration() -> dict[str, Any]:
    entry = _active_or_none()
    if entry is None:
        selected = run_gallery_manager(require_selection=True)
        if selected is None:
            raise RuntimeError("Nessuna galleria selezionata.")
        entry = selected
    configure_gallery(entry)
    return entry


def _unique_new_gallery(parent: Path, requested_name: str) -> Path:
    cleaned = " ".join(requested_name.split()).strip() or "H-Gallery"
    candidate = parent / cleaned
    if not candidate.exists():
        return candidate
    counter = 1
    while True:
        candidate = parent / f"{cleaned} {counter:02d}"
        if not candidate.exists():
            return candidate
        counter += 1


def run_gallery_manager(*, require_selection: bool = False) -> dict[str, Any] | None:
    """Apre il gestore grafico delle gallerie; usa il terminale come fallback."""

    try:
        import tkinter as tk
        from tkinter import filedialog, messagebox, simpledialog, ttk
    except ImportError:
        return _run_text_manager(require_selection=require_selection)

    result: dict[str, Any] = {"selected": None}
    try:
        root = tk.Tk()
    except tk.TclError:
        return _run_text_manager(require_selection=require_selection)
    root.title("H-Gallery - Gestione gallerie")
    root.geometry("760x460")
    root.minsize(660, 400)

    main = ttk.Frame(root, padding=18)
    main.pack(fill="both", expand=True)
    ttk.Label(main, text="Gallerie H-Gallery", font=("Segoe UI", 16, "bold")).pack(anchor="w")
    ttk.Label(
        main,
        text=(
            "Seleziona l'archivio da usare. Il programma può trovarsi in una "
            "cartella diversa dalle immagini."
        ),
        wraplength=700,
    ).pack(anchor="w", pady=(4, 14))

    columns = ("name", "path", "status")
    tree = ttk.Treeview(main, columns=columns, show="headings", selectmode="browse")
    tree.heading("name", text="Nome")
    tree.heading("path", text="Percorso")
    tree.heading("status", text="Stato")
    tree.column("name", width=150, minwidth=110)
    tree.column("path", width=430, minwidth=260)
    tree.column("status", width=90, minwidth=80, anchor="center")
    tree.pack(fill="both", expand=True)

    info_var = tk.StringVar(value=f"Configurazione: {REGISTRY_PATH}")
    ttk.Label(main, textvariable=info_var, wraplength=700).pack(anchor="w", pady=(10, 6))

    buttons = ttk.Frame(main)
    buttons.pack(fill="x", pady=(4, 0))

    def selected_id() -> str | None:
        selection = tree.selection()
        return selection[0] if selection else None

    def refresh(select_id: str | None = None) -> None:
        for item in tree.get_children():
            tree.delete(item)
        data = list_galleries(script_root=SCRIPT_ROOT)
        for gallery in data["results"]:
            status = "Attiva" if gallery["active"] else ("Disponibile" if gallery["available"] else "Assente")
            tree.insert(
                "",
                "end",
                iid=gallery["id"],
                values=(gallery["name"], gallery["path"], status),
            )
        target = select_id or data.get("active_gallery_id")
        if target and tree.exists(target):
            tree.selection_set(target)
            tree.focus(target)
            tree.see(target)

    def use_selected() -> None:
        gallery_id = selected_id()
        if not gallery_id:
            messagebox.showinfo("H-Gallery", "Seleziona una galleria dall'elenco.", parent=root)
            return
        try:
            entry = set_active_gallery(gallery_id)
            configure_gallery(entry)
        except (OSError, ValueError, RuntimeError) as error:
            messagebox.showerror("H-Gallery", str(error), parent=root)
            return
        result["selected"] = entry
        messagebox.showinfo(
            "H-Gallery",
            "Galleria attiva aggiornata.",
            parent=root,
        )
        root.destroy()

    def add_existing() -> None:
        path = filedialog.askdirectory(title="Seleziona una galleria esistente", parent=root)
        if not path:
            return
        try:
            entry = register_gallery(path, make_active=True, create_layout=True)
            configure_gallery(entry)
        except (OSError, ValueError, RuntimeError) as error:
            messagebox.showerror("H-Gallery", str(error), parent=root)
            return
        result["selected"] = entry
        refresh(entry["id"])
        info_var.set(f"Galleria aggiunta: {entry['path']}")

    def create_new() -> None:
        parent = filedialog.askdirectory(
            title="Seleziona dove creare la nuova galleria",
            parent=root,
        )
        if not parent:
            return
        name = simpledialog.askstring(
            "Nuova galleria",
            "Nome della cartella e della galleria:",
            initialvalue="H-Gallery",
            parent=root,
        )
        if name is None:
            return
        destination = _unique_new_gallery(Path(parent), name)
        try:
            entry = register_gallery(
                destination,
                name=destination.name,
                make_active=True,
                create_layout=True,
            )
            configure_gallery(entry)
        except (OSError, ValueError, RuntimeError) as error:
            messagebox.showerror("H-Gallery", str(error), parent=root)
            return
        result["selected"] = entry
        refresh(entry["id"])
        info_var.set(f"Nuova galleria creata: {entry['path']}")

    def remove_selected() -> None:
        gallery_id = selected_id()
        if not gallery_id:
            return
        registry = load_registry()
        entry = next((item for item in registry["galleries"] if item["id"] == gallery_id), None)
        if entry is None:
            return
        confirmed = messagebox.askyesno(
            "Rimuovi dall'elenco",
            (
                f"Rimuovere '{entry['name']}' dall'elenco?\n\n"
                "La cartella e tutti i file resteranno intatti."
            ),
            parent=root,
        )
        if not confirmed:
            return
        remove_gallery(gallery_id)
        refresh()

    ttk.Button(buttons, text="Usa selezionata", command=use_selected).pack(side="left")
    ttk.Button(buttons, text="Aggiungi esistente", command=add_existing).pack(side="left", padx=(8, 0))
    ttk.Button(buttons, text="Crea nuova", command=create_new).pack(side="left", padx=(8, 0))
    ttk.Button(buttons, text="Rimuovi dall'elenco", command=remove_selected).pack(side="left", padx=(8, 0))
    ttk.Button(buttons, text="Chiudi", command=root.destroy).pack(side="right")

    tree.bind("<Double-1>", lambda _event: use_selected())
    refresh()

    if require_selection and not tree.get_children():
        info_var.set("Nessuna galleria configurata: aggiungine una esistente o creane una nuova.")

    root.mainloop()
    return result["selected"] or _active_or_none()


def _run_text_manager(*, require_selection: bool = False) -> dict[str, Any] | None:
    data = list_galleries(script_root=SCRIPT_ROOT)
    if data["results"]:
        print("\nGallerie configurate:")
        for index, item in enumerate(data["results"], start=1):
            marker = "*" if item["active"] else " "
            print(f"{marker} {index}. {item['name']} — {item['path']}")
    path = input("\nPercorso della galleria da usare (vuoto per annullare): ").strip()
    if not path:
        if require_selection:
            return None
        return _active_or_none()
    entry = register_gallery(path, make_active=True, create_layout=True)
    configure_gallery(entry)
    return entry


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Configura le gallerie di H-Gallery.")
    parser.add_argument("--ensure", action="store_true", help="assicura che esista una galleria attiva")
    parser.add_argument("--manage", action="store_true", help="apre il gestore delle gallerie")
    parser.add_argument("--gallery", type=str, help="registra e usa una galleria esistente")
    parser.add_argument("--create", type=str, help="crea e usa una nuova galleria nel percorso indicato")
    parser.add_argument("--list", action="store_true", help="elenca le gallerie configurate")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.list:
            print(json.dumps(list_galleries(script_root=SCRIPT_ROOT), ensure_ascii=False, indent=2))
            return 0
        if args.gallery:
            entry = register_gallery(args.gallery, make_active=True, create_layout=True)
            configure_gallery(entry)
        elif args.create:
            entry = register_gallery(args.create, make_active=True, create_layout=True)
            configure_gallery(entry)
        elif args.manage:
            entry = run_gallery_manager(require_selection=False)
            if entry is None:
                return 0
        else:
            entry = ensure_configuration()

        print("\nConfigurazione completata.")
        print(f"Galleria attiva: {entry['name']} — {entry['path']}")
        print(f"Registro gallerie: {REGISTRY_PATH}")
        print(f"Dati della galleria: {Path(entry['path']) / '.user'}")
        return 0
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as error:
        print(f"\nErrore durante la configurazione: {error}")
        return 1


if __name__ == "__main__":
    sys.exit(main())

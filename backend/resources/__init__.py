from __future__ import annotations

from pathlib import Path

RESOURCE_ROOT = Path(__file__).resolve().parent
PACKAGED_CONFIG_EXAMPLE_PATH = RESOURCE_ROOT / "config.example.json"
SOURCE_CONFIG_EXAMPLE_PATH = RESOURCE_ROOT.parent.parent / "config.example.json"

# Durante lo sviluppo e nell'installazione locale modificabile resta possibile
# personalizzare il modello nella radice del progetto. Nel wheel viene usata la
# copia inclusa nel pacchetto.
CONFIG_EXAMPLE_PATH = (
    SOURCE_CONFIG_EXAMPLE_PATH
    if SOURCE_CONFIG_EXAMPLE_PATH.is_file()
    else PACKAGED_CONFIG_EXAMPLE_PATH
)

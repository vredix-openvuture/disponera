"""Markdown quick-notes store — flat .md files with [[wikilinks]].

Notes live in $XDG_DATA_HOME/disponera/notes as plain files so they stay
greppable/syncable and any editor (or Obsidian itself) can open the folder.
"""

import os
import re
from datetime import datetime
from pathlib import Path

from PySide6.QtCore import Property, QObject, Signal, Slot

_WIKILINK = re.compile(r"\[\[([^\]]+)\]\]")


def notes_dir() -> Path:
    base = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local/share")
    d = Path(base) / "disponera" / "notes"
    d.mkdir(parents=True, exist_ok=True)
    return d


class NotesStore(QObject):
    notesChanged = Signal()

    @Property("QVariantList", notify=notesChanged)
    def notes(self):
        out = []
        for p in sorted(notes_dir().glob("*.md"), key=lambda p: p.stat().st_mtime, reverse=True):
            out.append({"name": p.stem, "path": str(p),
                        "mtime": p.stat().st_mtime})
        return out

    @Slot(str, result=str)
    def read(self, name: str) -> str:
        p = notes_dir() / (name + ".md")
        try:
            return p.read_text(encoding="utf-8")
        except OSError:
            return ""

    @Slot(str, str)
    def save(self, name: str, body: str) -> None:
        (notes_dir() / (name + ".md")).write_text(body, encoding="utf-8")
        self.notesChanged.emit()

    @Slot(result=str)
    def create(self) -> str:
        name = datetime.now().strftime("note-%Y%m%d-%H%M%S")
        self.save(name, "# " + name + "\n\n")
        return name

    @Slot(str, result="QVariantList")
    def links(self, body: str):
        """[[wikilink]] targets in a note body (for the graph, later)."""
        return _WIKILINK.findall(body or "")

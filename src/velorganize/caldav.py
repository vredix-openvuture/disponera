"""Bridge to velumeron's caldav-client.py (RFC 4791, stdlib-only).

The shell script owns the JSON-cache contract: every command prints the full
cache on stdout. velorganize reuses the script (and thereby the accounts in
$VELUMERON_USER_DIR/gui/caldav-accounts.json) instead of reimplementing CalDAV —
the shell's calendar menu and this app stay in sync by construction.
"""

import json
import os
import subprocess
from pathlib import Path

from PySide6.QtCore import Property, QObject, Signal, Slot


def _client_script() -> Path | None:
    base = os.environ.get("VELUMERON_DIR") or str(Path.home() / ".config/velumeron")
    p = Path(base) / "assets/scripts/caldav-client.py"
    return p if p.exists() else None


class CalDavBridge(QObject):
    """Exposes load/sync/mutations to QML; state is the parsed JSON cache."""

    cacheChanged = Signal()

    def __init__(self) -> None:
        super().__init__()
        self._cache: dict = {}

    def _run(self, *args: str) -> None:
        script = _client_script()
        if script is None:
            self._cache = {"error": "caldav-client.py not found (is velumeron installed?)"}
            self.cacheChanged.emit()
            return
        try:
            out = subprocess.run(
                ["python3", str(script), *args],
                capture_output=True, text=True, timeout=120, check=True,
            ).stdout
            self._cache = json.loads(out)
        except (OSError, subprocess.SubprocessError, json.JSONDecodeError) as e:
            self._cache = {"error": str(e)}
        self.cacheChanged.emit()

    @Property("QVariant", notify=cacheChanged)
    def cache(self):  # noqa: D102 — QML property
        return self._cache

    @Slot()
    def load(self) -> None:
        self._run("load")

    @Slot()
    def sync(self) -> None:
        self._run("sync")

    @Slot(str, str, str)
    def addTodo(self, cal_id: str, summary: str, due_ymd: str = "") -> None:
        args = ["add-todo", cal_id, summary] + ([due_ymd] if due_ymd else [])
        self._run(*args)

    @Slot(str, str, bool)
    def toggleTodo(self, cal_id: str, href: str, done: bool) -> None:
        self._run("toggle-todo", cal_id, href, "1" if done else "0")

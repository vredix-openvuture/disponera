"""Bridge to velumeron's caldav-client.py (RFC 4791, stdlib-only).

The shell script owns the JSON-cache contract: every command prints the full
cache on stdout. velorganize reuses the script (and thereby the accounts in
$VELUMERON_USER_DIR/gui/caldav-accounts.json) instead of reimplementing CalDAV —
the shell's calendar menu and this app stay in sync by construction. Commands
run through the serialized ScriptQueue (never blocking the GUI thread, never
two mutations in flight at once).
"""

import json
import os
from pathlib import Path

from PySide6.QtCore import Property, QObject, Signal, Slot

from .runner import ScriptQueue


def _client_script() -> Path | None:
    base = os.environ.get("VELUMERON_DIR") or str(Path.home() / ".config/velumeron")
    p = Path(base) / "assets/scripts/caldav-client.py"
    return p if p.exists() else None


class CalDavBridge(QObject):
    """Exposes load/sync/mutations to QML; state is the parsed JSON cache."""

    cacheChanged = Signal()
    stateChanged = Signal()

    def __init__(self) -> None:
        super().__init__()
        self._cache: dict = {}
        self._queue = ScriptQueue(self)
        self._queue.finished.connect(self._done)
        self._queue.busyChanged.connect(self.stateChanged)

    def _run(self, *args: str) -> None:
        script = _client_script()
        if script is None:
            self._cache = {"error": "caldav-client.py not found (is velumeron installed?)"}
            self.cacheChanged.emit()
            return
        self._queue.run(["python3", str(script), *args])

    def _done(self, out: str, code: int) -> None:
        out = out.strip()
        if not out:
            return
        try:
            self._cache = json.loads(out)
        except ValueError:
            return                      # keep the previous model on a garbled read
        self.cacheChanged.emit()

    @Property("QVariant", notify=cacheChanged)
    def cache(self):                    # noqa: D102 — QML property
        return self._cache

    @Property(bool, notify=stateChanged)
    def syncing(self) -> bool:          # noqa: D102
        return self._queue.has_queued("sync")

    @Slot()
    def load(self) -> None:
        self._run("load")

    @Slot()
    def sync(self) -> None:
        if not self._queue.has_queued("sync"):
            self._run("sync")

    @Slot(str, str, str)
    def addTodo(self, cal_id: str, summary: str, due_ymd: str = "") -> None:
        args = ["add-todo", cal_id, summary] + ([due_ymd] if due_ymd else [])
        self._run(*args)

    @Slot(str, str, bool)
    def toggleTodo(self, cal_id: str, href: str, done: bool) -> None:
        self._run("toggle-todo", cal_id, href, "1" if done else "0")

    @Slot(str, str, str, str, int)
    def addEvent(self, cal_id: str, summary: str, ymd: str,
                 hm: str = "", duration_min: int = 60) -> None:
        self._run("add-event", cal_id, summary, ymd, hm or "", str(duration_min or 60))

    @Slot(str, str)
    def deleteItem(self, cal_id: str, href: str) -> None:
        self._run("delete-item", cal_id, href)

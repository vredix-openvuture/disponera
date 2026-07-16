"""Bridge to velumeron's caldav-client.py (RFC 4791, stdlib-only).

The shell script owns the JSON-cache contract: every command prints the full
cache on stdout. velora reuses the script (and thereby the accounts in
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


def _cache_file() -> Path:
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return Path(base) / "velumeron" / "caldav-cache.json"


def _read_cache() -> dict:
    """Read the client's on-disk cache directly. `caldav-client.py load` prints
    this file byte-for-byte, so reading it in-process skips a ~70ms python
    subprocess spawn AND makes the data present before QML's first paint."""
    try:
        with open(_cache_file()) as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


class CalDavBridge(QObject):
    """Exposes load/sync/mutations to QML; state is the parsed JSON cache."""

    cacheChanged = Signal()
    stateChanged = Signal()

    def __init__(self) -> None:
        super().__init__()
        # This bridge renders calendars + events only; the 117KB `todos` slice is
        # dead weight here (the todo model reads it straight from disk), so drop it.
        self._cache = self._slim(_read_cache())
        self._queue = ScriptQueue(self)
        self._queue.finished.connect(self._done)
        self._queue.busyChanged.connect(self.stateChanged)

    @staticmethod
    def _slim(d: dict) -> dict:
        d.pop("todos", None)
        return d

    def _run(self, *args: str, env: dict | None = None) -> None:
        script = _client_script()
        if script is None:
            self._cache = {"error": "caldav-client.py not found (is velumeron installed?)"}
            self.cacheChanged.emit()
            return
        self._queue.run(["python3", str(script), *args], env=env)

    def _done(self, out: str, code: int) -> None:
        out = out.strip()
        if not out:
            return
        try:
            self._cache = self._slim(json.loads(out))
        except ValueError:
            return                      # keep the previous model on a garbled read
        self.cacheChanged.emit()

    @Property("QVariantList", notify=cacheChanged)
    def calendars(self):                # noqa: D102 — VEVENT/VTODO calendars, ~9KB
        return self._cache.get("calendars", [])

    @Property("QVariantList", notify=cacheChanged)
    def events(self):                   # noqa: D102 — the month view's source list
        return self._cache.get("events", [])

    @Property("QVariantList", notify=cacheChanged)
    def accounts(self):                 # noqa: D102 — one per configured CalDAV login
        return self._cache.get("accounts", [])

    @Property(str, notify=cacheChanged)
    def lastError(self):                # noqa: D102 — surfaces add-account/sync failures
        return self._cache.get("lastError") or self._cache.get("error") or ""

    @Property(bool, notify=stateChanged)
    def syncing(self) -> bool:          # noqa: D102
        return self._queue.has_queued("sync") or self._queue.has_queued("add-account")

    @Slot()
    def load(self) -> None:
        # In-process: `load` never touches the network, it just re-emits the cache
        # the sync path already wrote. No subprocess needed.
        self._cache = self._slim(_read_cache())
        self.cacheChanged.emit()

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
    def addEventFull(self, cal_id: str, ev_json: str) -> None:
        # QML passes JSON.stringify(ev) — a plain string avoids fragile QVariant
        # conversion of the nested categories/attendees arrays.
        self._run("add-event-full", cal_id, ev_json or "{}")

    @Slot(str, str, str)
    def updateEvent(self, cal_id: str, href: str, patch_json: str) -> None:
        self._run("update-event", cal_id, href, patch_json or "{}")

    @Slot(str, str)
    def deleteItem(self, cal_id: str, href: str) -> None:
        self._run("delete-item", cal_id, href)

    # ── account management (writes caldav-accounts.json via the client) ──────
    @Slot(str, str, str, str)
    def addAccount(self, name: str, url: str, username: str, password: str) -> None:
        # Password goes through the process environment, never the argv/cache.
        # The client validates the credentials, saves, and re-syncs in one shot.
        self._run("add-account", env={
            "CD_NAME": name.strip(), "CD_URL": url.strip(),
            "CD_USER": username.strip(), "CD_PASS": password,
        })

    @Slot(str)
    def removeAccount(self, name: str) -> None:
        self._run("remove-account", name)

    @Slot(str, str)
    def renameAccount(self, old: str, new: str) -> None:
        if new.strip() and new.strip() != old:
            self._run("rename-account", old, new.strip())

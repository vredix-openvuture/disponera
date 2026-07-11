"""Unified todo model for the app — Vikunja project tree + CalDAV lists.

MERGE SPEC (duplicated in velumeron's quickshell/calendar/TodoService.qml —
keep them in lockstep; both read the same two cache files, so they agree by
construction after any sync):

  project = { id: "vk:8"|"cd:<calId>", title, parentId (""=root), source,
              color, writable, openCount }
  task    = { id: "vk:16"|"cd:<calId>|<href>", projectId, title, done, doneMs,
              dueMs, priority (0..5 Vikunja scale), parentTaskId, notes,
              cal, href (cd only — kept for mutations) }

Rules: Vikunja first; drop every CalDAV account whose URL host equals the
Vikunja host (same data, richer over REST). iCal priorities (1=highest…9) map
onto Vikunja's 0..5. CalDAV RELATED-TO parents resolve within the same
calendar. Unlike the shell, the app ignores caldav_hidden in M1.
"""

import json
import os
import time
import urllib.parse
from pathlib import Path

from PySide6.QtCore import Property, QObject, Signal, Slot

from .runner import ScriptQueue


def _scripts_dir() -> Path:
    base = os.environ.get("VELUMERON_DIR") or str(Path.home() / ".config/velumeron")
    return Path(base) / "assets" / "scripts"


def _ical_prio(p) -> int:
    p = int(p or 0)
    if p <= 0:
        return 0
    if p == 1:
        return 5
    if p <= 4:
        return 4
    if p == 5:
        return 3
    if p <= 8:
        return 2
    return 1


class TodoBridge(QObject):
    """QML context property `Todo` — unified projects/tasks + mutations."""

    modelChanged = Signal()
    stateChanged = Signal()

    def __init__(self) -> None:
        super().__init__()
        self._vk: dict = {}
        self._cd: dict = {}
        self._last_error = ""
        self._vk_q = ScriptQueue(self)
        self._cd_q = ScriptQueue(self)
        self._vk_q.finished.connect(self._vk_done)
        self._cd_q.finished.connect(self._cd_done)
        self._vk_q.busyChanged.connect(self.stateChanged)
        self._cd_q.busyChanged.connect(self.stateChanged)

    # ── script plumbing ─────────────────────────────────────────────────────
    def _vk_run(self, *args: str) -> None:
        script = _scripts_dir() / "vikunja-client.py"
        if script.exists():
            self._vk_q.run(["python3", str(script), *args])

    def _cd_run(self, *args: str) -> None:
        script = _scripts_dir() / "caldav-client.py"
        if script.exists():
            self._cd_q.run(["python3", str(script), *args])

    def _vk_done(self, out: str, code: int) -> None:
        self._absorb(out, "_vk")

    def _cd_done(self, out: str, code: int) -> None:
        self._absorb(out, "_cd")

    def _absorb(self, out: str, attr: str) -> None:
        out = out.strip()
        if not out:
            return
        try:
            data = json.loads(out)
        except ValueError:
            return                      # keep the previous model on a garbled read
        setattr(self, attr, data)
        self._last_error = data.get("lastError") or ""
        self.modelChanged.emit()
        self.stateChanged.emit()

    # ── merge (see spec above) ──────────────────────────────────────────────
    def _vk_ok(self) -> bool:
        return (self._vk.get("source") or {}).get("ok") is True

    def _vk_host(self) -> str:
        return (self._vk.get("source") or {}).get("host", "")

    def _kept_calendars(self) -> list:
        hosts = {}
        for a in self._cd.get("accounts", []):
            hosts[a.get("name")] = urllib.parse.urlsplit(a.get("url") or "").netloc
        vk_ok, vk_host = self._vk_ok(), self._vk_host()
        return [c for c in self._cd.get("calendars", [])
                if c.get("vtodo")
                and not (vk_ok and hosts.get(c.get("account")) == vk_host)]

    def _merged(self) -> tuple[list, list]:
        projects, tasks = [], []
        if self._vk_ok():
            for p in self._vk.get("projects", []):
                projects.append({
                    "id": f"vk:{p.get('id', 0)}", "title": p.get("title") or "",
                    "parentId": f"vk:{p['parentId']}" if p.get("parentId") else "",
                    "source": "vikunja", "color": p.get("color") or "",
                    "writable": True, "openCount": 0,
                })
            for t in self._vk.get("tasks", []):
                tasks.append({
                    "id": f"vk:{t.get('id', 0)}", "projectId": f"vk:{t.get('projectId', 0)}",
                    "title": t.get("title") or "", "done": bool(t.get("done")),
                    "doneMs": t.get("doneMs") or 0, "dueMs": t.get("dueMs") or 0,
                    "priority": int(t.get("priority") or 0),
                    "parentTaskId": f"vk:{t['parentId']}" if t.get("parentId") else "",
                    "notes": t.get("notes") or "", "cal": "", "href": "",
                })
        kept = self._kept_calendars()
        kept_ids = {c.get("id") for c in kept}
        for c in kept:
            projects.append({
                "id": f"cd:{c.get('id')}", "title": c.get("name") or "",
                "parentId": "", "source": "caldav", "color": c.get("color") or "",
                "writable": c.get("writable") is True, "openCount": 0,
            })
        todos = [t for t in self._cd.get("todos", []) if t.get("cal") in kept_ids]
        by_uid = {(t.get("cal"), t.get("uid")): t for t in todos}
        for t in todos:
            parent = by_uid.get((t.get("cal"), t.get("parent"))) if t.get("parent") else None
            tasks.append({
                "id": f"cd:{t.get('cal')}|{t.get('href')}",
                "projectId": f"cd:{t.get('cal')}",
                "title": t.get("summary") or "", "done": bool(t.get("completed")),
                "doneMs": t.get("doneMs") or 0, "dueMs": t.get("dueMs") or 0,
                "priority": _ical_prio(t.get("priority")),
                "parentTaskId": (f"cd:{parent.get('cal')}|{parent.get('href')}"
                                 if parent else ""),
                "notes": t.get("notes") or "", "cal": t.get("cal"), "href": t.get("href"),
            })
        counts: dict = {}
        for t in tasks:
            if not t["done"]:
                counts[t["projectId"]] = counts.get(t["projectId"], 0) + 1
        for p in projects:
            p["openCount"] = counts.get(p["id"], 0)
        return projects, tasks

    # ── QML API ─────────────────────────────────────────────────────────────
    @Property("QVariantList", notify=modelChanged)
    def projects(self):                    # noqa: D102
        return self._merged()[0]

    @Property("QVariantList", notify=modelChanged)
    def tasks(self):                       # noqa: D102
        return self._merged()[1]

    @Property(bool, notify=stateChanged)
    def syncing(self) -> bool:             # noqa: D102
        return self._vk_q.has_queued("sync") or self._cd_q.has_queued("sync")

    @Property(str, notify=modelChanged)
    def lastError(self) -> str:            # noqa: D102
        return self._last_error

    @Property(int, notify=modelChanged)
    def syncedAt(self) -> int:             # noqa: D102
        return int(self._vk.get("syncedAt") or self._cd.get("syncedAt") or 0)

    @Slot()
    def load(self) -> None:
        self._vk_run("load")
        self._cd_run("load")

    @Slot()
    def sync(self) -> None:
        if not self._vk_q.has_queued("sync"):
            self._vk_run("sync")
        if not self._cd_q.has_queued("sync"):
            self._cd_run("sync")
        self.stateChanged.emit()

    @Slot(str, str, str, str)
    def addTask(self, project_id: str, title: str, due_ymd: str = "",
                parent_task_id: str = "") -> None:
        if project_id.startswith("vk:"):
            args = ["add-task", project_id[3:], title, due_ymd]
            if parent_task_id.startswith("vk:"):
                args.append(parent_task_id[3:])
            self._vk_run(*args)
        elif project_id.startswith("cd:"):
            args = ["add-todo", project_id[3:], title]
            if due_ymd:
                args.append(due_ymd)
            self._cd_run(*args)

    @Slot("QVariant")
    def toggleTask(self, task) -> None:
        task = dict(task or {})
        tid = str(task.get("id") or "")
        done = bool(task.get("done"))
        if tid.startswith("vk:"):
            nid = int(tid[3:])
            for t in self._vk.get("tasks", []):    # optimistic patch
                if t.get("id") == nid:
                    t["done"] = not done
                    t["doneMs"] = int(time.time() * 1000) if not done else 0
            self.modelChanged.emit()
            self._vk_run("toggle-task", str(nid), "0" if done else "1")
        elif tid.startswith("cd:"):
            for t in self._cd.get("todos", []):
                if t.get("cal") == task.get("cal") and t.get("href") == task.get("href"):
                    t["completed"] = not done
            self.modelChanged.emit()
            self._cd_run("toggle-todo", task.get("cal") or "", task.get("href") or "",
                         "0" if done else "1")

    @Slot("QVariant")
    def deleteTask(self, task) -> None:
        task = dict(task or {})
        tid = str(task.get("id") or "")
        if tid.startswith("vk:"):
            nid = int(tid[3:])
            self._vk["tasks"] = [t for t in self._vk.get("tasks", [])
                                 if t.get("id") != nid]
            self.modelChanged.emit()
            self._vk_run("delete-task", str(nid))
        elif tid.startswith("cd:"):
            self._cd["todos"] = [t for t in self._cd.get("todos", [])
                                 if not (t.get("cal") == task.get("cal")
                                         and t.get("href") == task.get("href"))]
            self.modelChanged.emit()
            self._cd_run("delete-item", task.get("cal") or "", task.get("href") or "")

    @Slot("QVariant", str)
    def setDue(self, task, due_ymd: str) -> None:   # vikunja only in M1
        tid = str(dict(task or {}).get("id") or "")
        if tid.startswith("vk:"):
            self._vk_run("set-due", tid[3:], due_ymd or "")

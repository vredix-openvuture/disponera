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
from datetime import datetime
from pathlib import Path

from PySide6.QtCore import Property, QObject, Signal, Slot

from .runner import ScriptQueue


def _scripts_dir() -> Path:
    base = os.environ.get("VELUMERON_DIR") or str(Path.home() / ".config/velumeron")
    return Path(base) / "assets" / "scripts"


def _cache_dir() -> Path:
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return Path(base) / "velumeron"


def _read_cache(name: str) -> dict:
    """Read a client's on-disk cache directly. Its `load` command prints the file
    verbatim, so reading it here skips a ~60ms python subprocess spawn and has the
    model populated before QML's first paint."""
    try:
        with open(_cache_dir() / name) as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def _ymd_ms(ymd: str) -> int:
    """YYYY-MM-DD → epoch ms, for optimistic patches below. Doesn't need to
    match the server's exact due_rfc3339 time-of-day — it only holds the UI
    over until the real value lands a subprocess round trip later."""
    if not ymd:
        return 0
    try:
        return int(datetime.strptime(ymd, "%Y-%m-%d").timestamp() * 1000)
    except ValueError:
        return 0


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
    # (title, next dueMs) — fired once the server CONFIRMS a recurring vikunja
    # task rolled over instead of staying done (see toggleTask/_absorb below).
    # "qlonglong" (not plain int/Signal(str, int)): dueMs is a ms epoch — a
    # 32-bit int overflows on it (that's the syncedAt bug fixed below too).
    recurringCompleted = Signal(str, "qlonglong")

    def __init__(self, local=None) -> None:
        super().__init__()
        # Populate straight from the on-disk caches (in-process, no subprocess) so
        # the model is ready before QML binds. `_cd` never reads events, so drop
        # that 597KB slice on the way in.
        self._vk: dict = _read_cache("vikunja-cache.json")
        self._cd: dict = _read_cache("caldav-cache.json")
        self._cd.pop("events", None)
        self._local = local            # LocalStore | None — local todo lists (#7)
        self._last_error = self._vk.get("lastError") or ""
        self._merged_cache: tuple | None = None   # invalidated on any data change
        self._pending_recurring: dict[int, str] = {}   # vk task id → title, set
        # when toggling a recurring task to done; resolved on the next vk response.
        self._temp_id = 0   # negative placeholder ids for optimistic addTask rows —
        # never collide with real (positive) vikunja ids, and vanish on their own
        # once _absorb() replaces self._vk with the server's confirmed cache.
        self._vk_q = ScriptQueue(self)
        self._cd_q = ScriptQueue(self)
        self._vk_q.finished.connect(self._vk_done)
        self._cd_q.finished.connect(self._cd_done)
        self._vk_q.busyChanged.connect(self.stateChanged)
        self._cd_q.busyChanged.connect(self.stateChanged)
        if local is not None:
            local.changed.connect(self._touch)

    def _touch(self) -> None:
        """Invalidate the merged cache and notify. EVERY model mutation goes
        through here — `_merged()` is expensive (rebuilds + sorts all tasks), and
        `projects`/`tasks` are read by many bindings (calendar grid, board, detail
        pane), so recomputing per-access made a single checkbox toggle rebuild the
        whole model dozens of times → the "unresponsive" feel."""
        self._merged_cache = None
        self.modelChanged.emit()

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
        if attr == "_cd":
            data.pop("events", None)    # keep the 597KB events slice out of _cd
        setattr(self, attr, data)
        self._last_error = data.get("lastError") or ""
        if attr == "_vk" and self._pending_recurring:
            pending, self._pending_recurring = self._pending_recurring, {}
            for nid, title in pending.items():
                fresh = next((t for t in data.get("tasks", []) if t.get("id") == nid), None)
                if fresh is not None and not fresh.get("done"):
                    self.recurringCompleted.emit(title, int(fresh.get("dueMs") or 0))
        self._touch()
        self.stateChanged.emit()

    # ── merge (see spec above) ──────────────────────────────────────────────
    def _vk_ok(self) -> bool:
        return (self._vk.get("source") or {}).get("ok") is True

    def _vk_host(self) -> str:
        return (self._vk.get("source") or {}).get("host", "")

    def _role_of(self, account: str) -> str:
        return self._local.role_of(account) if self._local is not None else "both"

    def _kept_calendars(self) -> list:
        hosts = {}
        for a in self._cd.get("accounts", []):
            hosts[a.get("name")] = urllib.parse.urlsplit(a.get("url") or "").netloc
        vk_ok, vk_host = self._vk_ok(), self._vk_host()
        # A connection set to "calendar-only" (blueprint #6) contributes no task
        # lists; "tasks"/"both" keep them.
        return [c for c in self._cd.get("calendars", [])
                if c.get("vtodo")
                and self._role_of(c.get("account")) in ("both", "tasks")
                and not (vk_ok and hosts.get(c.get("account")) == vk_host)]

    def _merged(self) -> tuple[list, list]:
        projects, tasks = [], []
        if self._vk_ok():
            for p in self._vk.get("projects", []):
                projects.append({
                    "id": f"vk:{p.get('id', 0)}", "title": p.get("title") or "",
                    "parentId": f"vk:{p['parentId']}" if p.get("parentId") else "",
                    "source": "vikunja", "color": p.get("color") or "",
                    "description": p.get("description") or "",
                    "writable": True, "openCount": 0,
                    "bgPath": p.get("bgPath") or "", "blurHash": p.get("blurHash") or "",
                })
            for t in self._vk.get("tasks", []):
                tasks.append({
                    "id": f"vk:{t.get('id', 0)}", "projectId": f"vk:{t.get('projectId', 0)}",
                    "title": t.get("title") or "", "done": bool(t.get("done")),
                    "doneMs": t.get("doneMs") or 0, "dueMs": t.get("dueMs") or 0,
                    "priority": int(t.get("priority") or 0),
                    "parentTaskId": f"vk:{t['parentId']}" if t.get("parentId") else "",
                    "notes": t.get("notes") or "", "labels": t.get("labels") or [],
                    "recurring": bool(t.get("recurring")), "cal": "", "href": "",
                })
        kept = self._kept_calendars()
        kept_ids = {c.get("id") for c in kept}
        for c in kept:
            projects.append({
                "id": f"cd:{c.get('id')}", "title": c.get("name") or "",
                "parentId": "", "source": "caldav", "color": c.get("color") or "",
                "writable": c.get("writable") is True, "openCount": 0,
                "bgPath": "", "blurHash": "",
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
                "notes": t.get("notes") or "", "labels": [],
                "cal": t.get("cal"), "href": t.get("href"),
            })
        if self._local is not None:            # local todo lists (#7)
            projects.extend(self._local.todo_projects())
            tasks.extend(self._local.todo_tasks())
        counts: dict = {}
        for t in tasks:
            if not t["done"]:
                counts[t["projectId"]] = counts.get(t["projectId"], 0) + 1
        for p in projects:
            p["openCount"] = counts.get(p["id"], 0)
        return projects, tasks

    # ── QML API ─────────────────────────────────────────────────────────────
    def _merged_cached(self):
        if self._merged_cache is None:
            self._merged_cache = self._merged()
        return self._merged_cache

    @Property("QVariantList", notify=modelChanged)
    def projects(self):                    # noqa: D102
        return self._merged_cached()[0]

    @Property("QVariantList", notify=modelChanged)
    def tasks(self):                       # noqa: D102
        return self._merged_cached()[1]

    @Property("QVariantList", notify=modelChanged)
    def labels(self):                      # noqa: D102
        return self._vk.get("labels", []) if self._vk_ok() else []

    @Property(bool, notify=stateChanged)
    def syncing(self) -> bool:             # noqa: D102
        return self._vk_q.has_queued("sync") or self._cd_q.has_queued("sync")

    @Property(str, notify=modelChanged)
    def lastError(self) -> str:            # noqa: D102
        return self._last_error

    @Property("qlonglong", notify=modelChanged)   # ms epoch — overflows plain int
    def syncedAt(self) -> int:             # noqa: D102
        return int(self._vk.get("syncedAt") or self._cd.get("syncedAt") or 0)

    @Slot()
    def load(self) -> None:
        # In-process cache read (see __init__): no subprocess, no network.
        self._vk = _read_cache("vikunja-cache.json")
        self._cd = _read_cache("caldav-cache.json")
        self._cd.pop("events", None)
        self._last_error = self._vk.get("lastError") or ""
        self._touch()
        self.stateChanged.emit()

    @Slot()
    def reloadCaldav(self) -> None:
        """Re-read only the CalDAV cache from disk (in-process). Wired to
        CalDavBridge.cacheChanged in app.py so a SINGLE caldav sync/mutation
        refreshes both the calendar and this todo model — no second subprocess
        and no second network round-trip to the CalDAV servers."""
        cd = _read_cache("caldav-cache.json")
        cd.pop("events", None)
        self._cd = cd
        self._touch()
        self.stateChanged.emit()

    @Slot()
    def sync(self) -> None:
        # Only Vikunja hits the network here; the CalDAV network sync is owned by
        # CalDavBridge (its completion is wired to reloadCaldav), so the
        # 34-calendar sync runs ONCE instead of twice concurrently at startup.
        if not self._vk_q.has_queued("sync"):
            self._vk_run("sync")
        self.stateChanged.emit()

    @Slot(str, str, str, str)
    def addTask(self, project_id: str, title: str, due_ymd: str = "",
                parent_task_id: str = "") -> None:
        title = title.strip()
        if not title:
            return
        if project_id.startswith("vk:"):
            args = ["add-task", project_id[3:], title, due_ymd]
            if parent_task_id.startswith("vk:"):
                args.append(parent_task_id[3:])
            self._temp_id -= 1
            self._vk.setdefault("tasks", []).append({   # optimistic placeholder —
                # superseded wholesale once _absorb() lands the server's real
                # task (with a real id) from this same add-task call.
                "id": self._temp_id, "projectId": int(project_id[3:]), "title": title,
                "done": False, "doneMs": 0, "dueMs": _ymd_ms(due_ymd), "priority": 0,
                "percentDone": 0,
                "parentId": int(parent_task_id[3:]) if parent_task_id.startswith("vk:") else 0,
                "notes": "", "labels": [], "recurring": False,
                "updatedMs": int(time.time() * 1000),
            })
            self._touch()
            self._vk_run(*args)
        elif project_id.startswith("cd:"):
            args = ["add-todo", project_id[3:], title]
            if due_ymd:
                args.append(due_ymd)
            self._temp_id -= 1
            self._cd.setdefault("todos", []).append({   # optimistic placeholder —
                # superseded wholesale once _absorb() lands the server's real
                # todo (with a real href) from this same add-todo call.
                "cal": project_id[3:], "href": f"__pending_{self._temp_id}__",
                "etag": "", "uid": "", "summary": title, "notes": "",
                "dueMs": _ymd_ms(due_ymd), "dueAllDay": False, "completed": False,
                "doneMs": 0, "priority": 0, "parent": "",
            })
            self._touch()
            self._cd_run(*args)
        elif project_id.startswith("loc:") and self._local is not None:
            self._local.addTodo(project_id[4:], title, due_ymd or "")

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
            if not done and task.get("recurring"):
                # Vikunja resets a recurring task's done back to False and
                # advances dueMs instead of leaving it checked — the optimistic
                # patch above gets overwritten once _absorb() lands the server's
                # confirmed state, so tell the user why via recurringCompleted
                # instead of the row just silently flickering back.
                self._pending_recurring[nid] = task.get("title") or ""
            self._touch()
            self._vk_run("toggle-task", str(nid), "0" if done else "1")
        elif tid.startswith("cd:"):
            for t in self._cd.get("todos", []):
                if t.get("cal") == task.get("cal") and t.get("href") == task.get("href"):
                    t["completed"] = not done
            self._touch()
            self._cd_run("toggle-todo", task.get("cal") or "", task.get("href") or "",
                         "0" if done else "1")
        elif tid.startswith("loc:") and self._local is not None:
            self._local.toggleItem(tid[4:])

    @Slot("QVariant")
    def deleteTask(self, task) -> None:
        task = dict(task or {})
        tid = str(task.get("id") or "")
        if tid.startswith("vk:"):
            nid = int(tid[3:])
            self._vk["tasks"] = [t for t in self._vk.get("tasks", [])
                                 if t.get("id") != nid]
            self._touch()
            self._vk_run("delete-task", str(nid))
        elif tid.startswith("cd:"):
            self._cd["todos"] = [t for t in self._cd.get("todos", [])
                                 if not (t.get("cal") == task.get("cal")
                                         and t.get("href") == task.get("href"))]
            self._touch()
            self._cd_run("delete-item", task.get("cal") or "", task.get("href") or "")
        elif tid.startswith("loc:") and self._local is not None:
            self._local.deleteItem(tid[4:])

    @Slot("QVariant", str)
    def setDue(self, task, due_ymd: str) -> None:
        tid = str(dict(task or {}).get("id") or "")
        if tid.startswith("vk:"):
            nid = int(tid[3:])
            for t in self._vk.get("tasks", []):    # optimistic patch
                if t.get("id") == nid:
                    t["dueMs"] = _ymd_ms(due_ymd)
            self._touch()
            self._vk_run("set-due", tid[3:], due_ymd or "")
        elif tid.startswith("loc:") and self._local is not None:
            self._local.updateItem(tid[4:], {"ymd": due_ymd or ""})

    # ── Full project & task CRUD (blueprint #8, vikunja) ─────────────────────
    @Slot(str, str, str, str)
    def addProject(self, title: str, parent_id: str = "", color: str = "",
                   description: str = "") -> None:
        title = title.strip()
        if not title:
            return
        parent = parent_id[3:] if parent_id.startswith("vk:") else ""
        self._temp_id -= 1
        self._vk.setdefault("projects", []).append({    # optimistic placeholder —
            # superseded wholesale once _absorb() lands the server's real
            # project (with a real id) from this same add-project call.
            "id": self._temp_id, "title": title,
            "parentId": int(parent) if parent else 0,
            "color": color or "", "description": description or "",
            "archived": False, "favorite": False,
            "hasBg": False, "blurHash": "", "bgPath": "",
        })
        self._touch()
        self._vk_run("add-project", title, parent, color or "", description or "")

    @Slot(str, "QVariant")
    def updateProject(self, project_id: str, patch) -> None:
        if not project_id.startswith("vk:"):
            return
        nid = int(project_id[3:])
        p = dict(patch or {})
        if "parentId" in p:                 # QML sends "vk:8" or "" — CLI wants an int
            pv = str(p["parentId"] or "")
            p["parentId"] = pv[3:] if pv.startswith("vk:") else (pv or "0")
        for proj in self._vk.get("projects", []):    # optimistic patch
            if proj.get("id") == nid:
                if "title" in p: proj["title"] = p["title"]
                if "color" in p: proj["color"] = p["color"]
                if "description" in p: proj["description"] = p["description"]
                if "parentId" in p: proj["parentId"] = int(p["parentId"] or 0)
        self._touch()
        self._vk_run("update-project", project_id[3:], json.dumps(p))

    @Slot(str)
    def deleteProject(self, project_id: str) -> None:
        if not project_id.startswith("vk:"):
            return
        nid = int(project_id[3:])
        self._vk["projects"] = [p for p in self._vk.get("projects", [])   # optimistic
                                if p.get("id") != nid]
        self._vk["tasks"] = [t for t in self._vk.get("tasks", [])
                             if t.get("projectId") != nid]
        self._touch()
        self._vk_run("delete-project", str(nid))

    @Slot("QVariant", "QVariant")
    def updateTask(self, task, patch) -> None:
        tid = str(dict(task or {}).get("id") or "")
        if tid.startswith("vk:"):
            nid = int(tid[3:])
            p = dict(patch or {})
            for t in self._vk.get("tasks", []):    # optimistic patch
                if t.get("id") == nid:
                    if "title" in p: t["title"] = p["title"]
                    if "notes" in p: t["notes"] = p["notes"]
                    if "priority" in p: t["priority"] = int(p["priority"] or 0)
                    if "dueYmd" in p: t["dueMs"] = _ymd_ms(p["dueYmd"])
            self._touch()
            self._vk_run("update-task", tid[3:], json.dumps(p))
        elif tid.startswith("loc:") and self._local is not None:
            p = dict(patch or {})
            lp = {}
            if "title" in p: lp["title"] = p["title"]
            if "notes" in p: lp["notes"] = p["notes"]
            if "priority" in p: lp["priority"] = p["priority"]
            if "dueYmd" in p: lp["ymd"] = p["dueYmd"]
            self._local.updateItem(tid[4:], lp)

    @Slot("QVariant", str)
    def moveTask(self, task, new_project_id: str) -> None:
        tid = str(dict(task or {}).get("id") or "")
        if tid.startswith("vk:") and new_project_id.startswith("vk:"):
            nid, npid = int(tid[3:]), int(new_project_id[3:])
            for t in self._vk.get("tasks", []):    # optimistic patch
                if t.get("id") == nid:
                    t["projectId"] = npid
            self._touch()
            self._vk_run("move-task", tid[3:], new_project_id[3:])

    @Slot("QVariant", "QVariant")
    def setLabels(self, task, label_ids) -> None:
        tid = str(dict(task or {}).get("id") or "")
        if tid.startswith("vk:"):
            ids = [int(x) for x in (label_ids or [])]
            self._vk_run("set-labels", tid[3:], json.dumps(ids))

    @Slot(str, str)
    def addLabel(self, title: str, color: str = "") -> None:
        title = title.strip()
        if title:
            self._vk_run("add-label", title, color or "")

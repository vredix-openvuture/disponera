"""Local-only store: calendars / todo lists that live on this machine with no
CalDAV server (blueprint #7), plus the two Integrations extras that are pure
local metadata (blueprint #6): per-CalDAV-account role and ICS subscriptions.

Everything persists to $XDG_CONFIG_HOME/disponera/local.json. The store shapes
its lists/todos/events to the SAME dicts the Vikunja/CalDAV bridges emit, so the
Todo model and the calendar can union them in with a `loc:`/`ics:` id prefix and
otherwise treat them identically.

ICS subscriptions are read-only calendar feeds: their .ics is fetched off-thread
(never blocks the GUI) and parsed for VEVENTs into calendar events.
"""

import json
import os
import shutil
import ssl
import threading
import time
import urllib.request
import uuid
from datetime import datetime, timedelta
from pathlib import Path

from PySide6.QtCore import Property, QObject, Signal, Slot


def _config_dir() -> Path:
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    d = Path(base) / "disponera"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _now_ms() -> int:
    return int(time.time() * 1000)


def _ymd_to_ms(ymd: str, hm: str = "") -> int:
    if not ymd:
        return 0
    try:
        if hm:
            dt = datetime.strptime(f"{ymd} {hm}", "%Y-%m-%d %H:%M")
        else:
            dt = datetime.strptime(ymd, "%Y-%m-%d")
        return int(dt.timestamp() * 1000)
    except ValueError:
        return 0


# ── minimal iCalendar VEVENT parser (SUMMARY / DTSTART / DTEND) ───────────────

def _ical_dt_ms(value: str, params: str):
    """An iCal date or date-time → (epoch_ms, all_day)."""
    v = (value or "").strip()
    all_day = "VALUE=DATE" in (params or "").upper() or (len(v) == 8 and v.isdigit())
    try:
        if all_day:
            return int(datetime.strptime(v[:8], "%Y%m%d").timestamp() * 1000), True
        vv = v.rstrip("Z")
        dt = datetime.strptime(vv[:15], "%Y%m%dT%H%M%S")
        return int(dt.timestamp() * 1000), False
    except ValueError:
        return 0, all_day


def _parse_ics(text: str, cal_id: str):
    """Unfold lines, pull each VEVENT's SUMMARY/DTSTART/DTEND into an event dict
    matching caldav-client's event shape."""
    lines, out = [], []
    for raw in (text or "").splitlines():
        if raw[:1] in (" ", "\t") and lines:
            lines[-1] += raw[1:]
        else:
            lines.append(raw)
    cur = None
    for ln in lines:
        if ln.startswith("BEGIN:VEVENT"):
            cur = {"summary": "", "startMs": 0, "endMs": 0, "allDay": False, "cal": cal_id}
        elif ln.startswith("END:VEVENT"):
            if cur is not None:
                if cur["endMs"] <= cur["startMs"]:
                    cur["endMs"] = cur["startMs"] + (86400000 if cur["allDay"] else 3600000)
                if cur["startMs"] > 0:
                    out.append(cur)
            cur = None
        elif cur is not None:
            name, _, val = ln.partition(":")
            key, _, params = name.partition(";")
            key = key.upper()
            if key == "SUMMARY":
                cur["summary"] = val.replace("\\,", ",").replace("\\n", " ").strip()
            elif key == "DTSTART":
                cur["startMs"], cur["allDay"] = _ical_dt_ms(val, params)
            elif key == "DTEND":
                cur["endMs"], _ = _ical_dt_ms(val, params)
    return out


class LocalStore(QObject):
    """QML context property `Local` — local lists/items + ICS subs + roles."""

    changed = Signal()          # lists / items / roles mutated
    # Any change that alters the shaped `events` list — a local item mutation
    # (_save) OR a background ICS refetch. `events` MUST be notified by this and
    # not by `changed` alone: a QML property can bind to only one NOTIFY signal,
    # and if `events` listened to `icsChanged` only (the old bug), creating or
    # editing a local event — which emits `changed` — never refreshed the
    # calendar until some unrelated icsChanged/CalDav sync fired ("save does
    # nothing" / "new event takes forever to show").
    eventsChanged = Signal()

    def __init__(self) -> None:
        super().__init__()
        self._path = _config_dir() / "local.json"
        self._data = self._load()
        self._ics_events: list = []
        self.refreshIcs()

    # ── persistence ─────────────────────────────────────────────────────────
    def _load(self) -> dict:
        try:
            with open(self._path) as f:
                d = json.load(f)
            if isinstance(d, dict):
                d.setdefault("lists", []); d.setdefault("items", [])
                d.setdefault("ics", []); d.setdefault("roles", {})
                d.setdefault("eventTags", [])
                return d
        except (OSError, ValueError):
            pass
        return {"lists": [], "items": [], "ics": [], "roles": {}, "eventTags": []}

    def _save(self) -> None:
        tmp = str(self._path) + ".tmp"
        with open(tmp, "w") as f:
            json.dump(self._data, f, indent=2)
        os.replace(tmp, self._path)
        self.changed.emit()
        # A local item change also changes the shaped events list — fire the
        # events notification so calendar bindings recompute immediately.
        self.eventsChanged.emit()

    def _list(self, list_id: str):
        return next((l for l in self._data["lists"] if l["id"] == list_id), None)

    # ── QML-facing raw collections ──────────────────────────────────────────
    @Property("QVariantList", notify=changed)
    def lists(self):
        return self._data["lists"]

    @Property("QVariantList", notify=changed)
    def icsSubs(self):
        return self._data["ics"]

    @Property("QVariant", notify=changed)
    def roles(self):
        return self._data["roles"]

    # ── shaped projects/tasks for the Todo model (Python consumers) ─────────
    def todo_projects(self):
        out = []
        for l in self._data["lists"]:
            if l.get("kind") == "todo":
                out.append({
                    "id": f"loc:{l['id']}", "title": l.get("name") or "", "parentId": "",
                    "source": "local", "color": l.get("color") or "", "description": "",
                    "writable": True, "openCount": 0, "bgPath": "", "blurHash": "",
                })
        return out

    def todo_tasks(self):
        out = []
        for it in self._data["items"]:
            l = self._list(it.get("listId"))
            if not l or l.get("kind") != "todo":
                continue
            out.append({
                "id": f"loc:{it['id']}", "projectId": f"loc:{it['listId']}",
                "title": it.get("title") or "", "done": bool(it.get("done")),
                "doneMs": it.get("doneMs") or 0, "dueMs": _ymd_to_ms(it.get("ymd", "")),
                "priority": int(it.get("priority") or 0), "parentTaskId": "",
                "notes": it.get("notes") or "", "labels": [], "cal": "", "href": "",
            })
        return out

    # ── shaped calendars/events for the calendar (QML) ──────────────────────
    @Property("QVariantList", notify=changed)
    def calendars(self):
        out = []
        for l in self._data["lists"]:
            if l.get("kind") == "calendar":
                out.append({"id": f"loc:{l['id']}", "name": l.get("name") or "",
                            "color": l.get("color") or "", "vevent": True, "vtodo": False,
                            "writable": True, "account": "Local"})
        for s in self._data["ics"]:
            out.append({"id": f"ics:{s['id']}", "name": s.get("name") or "",
                        "color": s.get("color") or "", "vevent": True, "vtodo": False,
                        "writable": False, "account": "ICS"})
        return out

    @Property("QVariantList", notify=eventsChanged)
    def events(self):
        out = []
        for it in self._data["items"]:
            l = self._list(it.get("listId"))
            if not l or l.get("kind") != "calendar":
                continue
            start = _ymd_to_ms(it.get("ymd", ""), it.get("hm", ""))
            if not start:
                continue
            all_day = not it.get("hm")
            dur = int(it.get("durMin") or (0 if all_day else 60))
            end = start + (86400000 if all_day else dur * 60000)
            out.append({"cal": f"loc:{it['listId']}", "uid": it["id"], "href": it["id"],
                        "summary": it.get("title") or "", "startMs": start, "endMs": end,
                        "allDay": all_day, "recurring": False,
                        "notes": it.get("notes") or "", "location": it.get("location") or "",
                        "categories": it.get("categories") or [],
                        "attendees": it.get("attendees") or [], "icon": it.get("icon") or "",
                        "image": it.get("image") or ""})
        return out + self._ics_events

    # ── list CRUD ───────────────────────────────────────────────────────────
    @Slot(str, str, str, result=str)
    def addList(self, name: str, kind: str, color: str = "") -> str:
        name = name.strip()
        if not name:
            return ""
        lid = uuid.uuid4().hex[:8]
        self._data["lists"].append({"id": lid, "name": name,
                                    "kind": "calendar" if kind == "calendar" else "todo",
                                    "color": color or ""})
        self._save()
        return lid

    @Slot(str, str)
    def renameList(self, list_id: str, name: str) -> None:
        l = self._list(list_id)
        if l and name.strip():
            l["name"] = name.strip(); self._save()

    @Slot(str, str)
    def setListColor(self, list_id: str, color: str) -> None:
        l = self._list(list_id)
        if l:
            l["color"] = color; self._save()

    @Slot(str)
    def deleteList(self, list_id: str) -> None:
        self._data["lists"] = [l for l in self._data["lists"] if l["id"] != list_id]
        self._data["items"] = [i for i in self._data["items"] if i.get("listId") != list_id]
        self._save()

    # ── item CRUD (a todo or an event depending on its list) ────────────────
    @Slot(str, str, str, result=str)
    def addTodo(self, list_id: str, title: str, ymd: str = "") -> str:
        title = title.strip()
        if not title or not self._list(list_id):
            return ""
        iid = uuid.uuid4().hex[:8]
        self._data["items"].append({"id": iid, "listId": list_id, "title": title,
                                    "ymd": ymd or "", "done": False, "doneMs": 0,
                                    "priority": 0, "notes": ""})
        self._save()
        return iid

    @Slot(str, str, str, int, result=str)
    def addEvent(self, list_id: str, title: str, ymd: str, hm: str = "",
                 dur_min: int = 60) -> str:
        title = title.strip()
        if not title or not ymd or not self._list(list_id):
            return ""
        iid = uuid.uuid4().hex[:8]
        self._data["items"].append({"id": iid, "listId": list_id, "title": title,
                                    "ymd": ymd, "hm": hm or "", "durMin": int(dur_min or 60),
                                    "notes": ""})
        self._save()
        return iid

    @Slot(str, str, result=str)
    def addEventFull(self, list_id: str, ev_json: str) -> str:
        """Create a local event from a JSON event (mirrors CalDav.addEventFull)."""
        try:
            ev = json.loads(ev_json or "{}")
        except ValueError:
            return ""
        title = (ev.get("summary") or "").strip()
        if not title or not ev.get("ymd") or not self._list(list_id):
            return ""
        iid = uuid.uuid4().hex[:8]
        self._data["items"].append({
            "id": iid, "listId": list_id, "title": title, "ymd": ev.get("ymd"),
            "hm": ev.get("hm") or "", "durMin": int(ev.get("durMin") or 60),
            "notes": ev.get("notes") or "", "location": ev.get("location") or "",
            "categories": list(ev.get("categories") or []),
            "attendees": [dict(a) for a in (ev.get("attendees") or [])],
            "icon": ev.get("icon") or "", "image": ev.get("image") or ""})
        self._save()
        return iid

    def _item(self, item_id: str):
        return next((i for i in self._data["items"] if i["id"] == item_id), None)

    @Slot(str)
    def toggleItem(self, item_id: str) -> None:
        it = self._item(item_id)
        if it is not None:
            it["done"] = not it.get("done")
            it["doneMs"] = _now_ms() if it["done"] else 0
            self._save()

    @Slot(str)
    def deleteItem(self, item_id: str) -> None:
        self._data["items"] = [i for i in self._data["items"] if i["id"] != item_id]
        self._save()

    @Slot(str, str)
    def updateEventItem(self, item_id: str, patch_json: str) -> None:
        """Event update from a JSON patch (nested categories/attendees)."""
        try:
            self.updateItem(item_id, json.loads(patch_json or "{}"))
        except ValueError:
            pass

    @Slot(str, "QVariant")
    def updateItem(self, item_id: str, patch) -> None:
        it = self._item(item_id)
        if it is None:
            return
        p = dict(patch or {})
        if "summary" in p:                      # EventDialog uses "summary" for the title
            it["title"] = p["summary"]
        for k in ("title", "ymd", "hm", "notes", "location", "icon", "image"):
            if k in p:
                it[k] = p[k]
        if "priority" in p:
            it["priority"] = int(p["priority"] or 0)
        if "durMin" in p:
            it["durMin"] = int(p["durMin"] or 60)
        if "categories" in p:
            it["categories"] = list(p["categories"] or [])
        if "attendees" in p:
            it["attendees"] = [dict(a) for a in (p["attendees"] or [])]
        self._save()

    # ── reusable event tags (for the calendar's Tags picker) ────────────────
    @Property("QVariantList", notify=changed)
    def eventTags(self):
        return self._data.get("eventTags", [])

    @Slot(str, str, result=str)
    def addEventTag(self, name: str, color: str = "") -> str:
        name = name.strip()
        if not name:
            return ""
        self._data.setdefault("eventTags", [])
        if not any((t.get("name") or "").lower() == name.lower() for t in self._data["eventTags"]):
            self._data["eventTags"].append({"name": name, "color": color or ""})
            self._save()
        return name

    @Slot(str)
    def removeEventTag(self, name: str) -> None:
        self._data["eventTags"] = [t for t in self._data.get("eventTags", [])
                                   if t.get("name") != name]
        self._save()

    # ── event images: copy a picked file into a cache dir, return the path ──
    @Slot(str, result=str)
    def cacheImage(self, src: str) -> str:
        src = (src or "").replace("file://", "").strip()
        if not src or not os.path.isfile(src):
            return ""
        base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
        d = os.path.join(base, "disponera", "event-images")
        os.makedirs(d, exist_ok=True)
        ext = os.path.splitext(src)[1] or ".img"
        dst = os.path.join(d, uuid.uuid4().hex[:12] + ext)
        try:
            shutil.copyfile(src, dst)
        except OSError:
            return ""
        return dst

    # ── CalDAV account role (blueprint #6) ──────────────────────────────────
    @Slot(str, str)
    def setRole(self, account: str, role: str) -> None:
        if role not in ("both", "tasks", "calendar"):
            role = "both"
        self._data["roles"][account] = role
        self._save()

    def role_of(self, account: str) -> str:
        return self._data["roles"].get(account, "both")

    # ── ICS subscriptions (blueprint #6) ────────────────────────────────────
    @Slot(str, str, str, result=str)
    def addIcs(self, name: str, url: str, color: str = "") -> str:
        name, url = name.strip(), url.strip()
        if not url:
            return ""
        sid = uuid.uuid4().hex[:8]
        self._data["ics"].append({"id": sid, "name": name or url, "url": url, "color": color or ""})
        self._save()
        self.refreshIcs()
        return sid

    @Slot(str)
    def removeIcs(self, sub_id: str) -> None:
        self._data["ics"] = [s for s in self._data["ics"] if s["id"] != sub_id]
        self._save()
        self.refreshIcs()

    @Slot()
    def refreshIcs(self) -> None:
        subs = list(self._data["ics"])
        if not subs:
            self._ics_events = []
            self.eventsChanged.emit()
            return
        threading.Thread(target=self._fetch_ics, args=(subs,), daemon=True).start()

    def _fetch_ics(self, subs) -> None:
        collected = []
        ctx = ssl.create_default_context()
        for s in subs:
            try:
                req = urllib.request.Request(s["url"], headers={"User-Agent": "disponera-ics/1.0"})
                with urllib.request.urlopen(req, timeout=12, context=ctx) as r:
                    text = r.read().decode("utf-8", "replace")
                collected.extend(_parse_ics(text, f"ics:{s['id']}"))
            except Exception:                                       # noqa: BLE001
                continue
        self._ics_events = collected
        self.eventsChanged.emit()

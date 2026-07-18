"""Local per-calendar view preferences for Disponera.

Disponera deliberately keeps its own calendar visibility + colour overrides
separate from the shell — the app ignores the shell's caldav_hidden (see the
merge spec in todomodel). Preferences live in a flat JSON map at
$XDG_CONFIG_HOME/disponera/calendars.json so they survive restarts and stay
hand-editable. Written atomically (tmp + replace).
"""

import json
import os
from pathlib import Path

from PySide6.QtCore import Property, QObject, Signal, Slot
from PySide6.QtQml import QJSValue

from . import __version__


def _config_dir() -> Path:
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    d = Path(base) / "disponera"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _config_path() -> Path:
    return _config_dir() / "calendars.json"


# Themes Disponera can pin instead of following wallust. "auto" ⇒ live wallust
# palette (see theme.py THEMES for the pinned palettes).
THEME_IDS = ["auto", "gruvbox", "dracula", "nord", "catppuccin", "tokyonight"]

# Selectable default calendar views (mirrors CalendarPane's calView states).
VIEW_IDS = ["year", "month", "week", "day", "agenda"]


class AppSettings(QObject):
    """QML `Settings` — app-wide preferences persisted to settings.json.

    firstDayOfWeek: 0=Sunday … 6=Saturday (calendar grid start column).
    theme: one of THEME_IDS; "auto" follows the live wallust palette, any other
    value pins that named palette (theme.py reads this back).
    """

    changed = Signal()

    def __init__(self) -> None:
        super().__init__()
        self._first_dow = 1          # Monday, matching velumeron's default
        self._theme = "auto"
        self._past_event_opacity = 0.4   # week/day time grid: opacity of events already over
        self._hero_blur = 0.8            # event detail card: background image blur (0..1)
        self._hero_dim = 0.55            # event detail card: background image darkening (0..1)
        self._show_event_images = False  # week/day grid: paint an event's image behind its block
        self._time_24h = True            # 24-hour clock everywhere (else 12-hour AM/PM)
        self._startup_tab = 0            # tab shown on launch: 0=Calendar, 1=Todos
        self._default_view = "week"      # calendar view the app opens on (VIEW_IDS)
        self._day_start = 0              # week/day time grid: first visible hour (0..23)
        self._day_end = 24               # week/day time grid: last visible hour (1..24)
        self._load()

    def _path(self) -> Path:
        return _config_dir() / "settings.json"

    def _load(self) -> None:
        try:
            data = json.loads(self._path().read_text())
        except (OSError, ValueError):
            return
        fdow = data.get("firstDayOfWeek")
        if isinstance(fdow, int) and 0 <= fdow <= 6:
            self._first_dow = fdow
        theme = data.get("theme")
        if theme in THEME_IDS:
            self._theme = theme
        peo = data.get("pastEventOpacity")
        if isinstance(peo, (int, float)) and 0.05 <= peo <= 1.0:
            self._past_event_opacity = float(peo)
        for key, attr in (("heroBlur", "_hero_blur"), ("heroDim", "_hero_dim")):
            v = data.get(key)
            if isinstance(v, (int, float)) and 0.0 <= v <= 1.0:
                setattr(self, attr, float(v))
        if isinstance(data.get("showEventImages"), bool):
            self._show_event_images = data["showEventImages"]
        if isinstance(data.get("time24h"), bool):
            self._time_24h = data["time24h"]
        st = data.get("startupTab")
        if isinstance(st, int) and 0 <= st <= 1:
            self._startup_tab = st
        if data.get("defaultView") in VIEW_IDS:
            self._default_view = data["defaultView"]
        ds, de = data.get("dayStartHour"), data.get("dayEndHour")
        if isinstance(ds, int) and isinstance(de, int) and 0 <= ds < de <= 24:
            self._day_start, self._day_end = ds, de

    def _save(self) -> None:
        path = self._path()
        tmp = path.with_name(path.name + ".tmp")
        tmp.write_text(json.dumps(
            {"firstDayOfWeek": self._first_dow, "theme": self._theme,
             "pastEventOpacity": self._past_event_opacity,
             "heroBlur": self._hero_blur, "heroDim": self._hero_dim,
             "showEventImages": self._show_event_images,
             "time24h": self._time_24h, "startupTab": self._startup_tab,
             "defaultView": self._default_view,
             "dayStartHour": self._day_start, "dayEndHour": self._day_end}, indent=2))
        tmp.replace(path)

    @Property(int, notify=changed)
    def firstDayOfWeek(self):               # noqa: D102
        return self._first_dow

    @Property(str, notify=changed)
    def theme(self):                        # noqa: D102
        return self._theme

    @Property("QVariantList", constant=True)
    def themes(self):                       # noqa: D102 — selectable theme ids
        return THEME_IDS

    @Property(float, notify=changed)
    def pastEventOpacity(self):             # noqa: D102
        return self._past_event_opacity

    @Property(float, notify=changed)
    def heroBlur(self):                     # noqa: D102 — event card bg image blur (0..1)
        return self._hero_blur

    @Property(float, notify=changed)
    def heroDim(self):                      # noqa: D102 — event card bg image darkening (0..1)
        return self._hero_dim

    @Property(bool, notify=changed)
    def showEventImages(self):              # noqa: D102 — image behind week/day blocks
        return self._show_event_images

    @Property(bool, notify=changed)
    def time24h(self):                      # noqa: D102 — 24-hour vs 12-hour clock
        return self._time_24h

    # Qt time/date-time format strings derived from time24h, so QML call sites
    # read one property instead of branching on the clock mode everywhere.
    @Property(str, notify=changed)
    def timeFmt(self):                      # noqa: D102 — e.g. "hh:mm" / "h:mm AP"
        return "hh:mm" if self._time_24h else "h:mm AP"

    @Property(str, notify=changed)
    def dateTimeFmt(self):                  # noqa: D102 — "ddd, MMM d · <time>"
        return "ddd, MMM d · " + ("hh:mm" if self._time_24h else "h:mm AP")

    @Property(int, notify=changed)
    def startupTab(self):                   # noqa: D102 — 0=Calendar, 1=Todos
        return self._startup_tab

    @Property(str, notify=changed)
    def defaultView(self):                  # noqa: D102 — VIEW_IDS
        return self._default_view

    @Property("QVariantList", constant=True)
    def views(self):                        # noqa: D102 — selectable view ids
        return VIEW_IDS

    @Property(int, notify=changed)
    def dayStartHour(self):                 # noqa: D102 — first visible hour (0..23)
        return self._day_start

    @Property(int, notify=changed)
    def dayEndHour(self):                   # noqa: D102 — last visible hour (1..24)
        return self._day_end

    @Property(str, constant=True)
    def version(self):                      # noqa: D102 — app version, for About
        return __version__

    @Property(str, constant=True)
    def configDir(self):                    # noqa: D102 — where prefs are stored
        return str(_config_dir())

    @Slot(int)
    def setFirstDayOfWeek(self, dow: int) -> None:
        dow = int(dow)
        if 0 <= dow <= 6 and dow != self._first_dow:
            self._first_dow = dow
            self._save()
            self.changed.emit()

    @Slot(str)
    def setTheme(self, theme: str) -> None:
        if theme in THEME_IDS and theme != self._theme:
            self._theme = theme
            self._save()
            self.changed.emit()

    @Slot(float)
    def setPastEventOpacity(self, v: float) -> None:
        v = max(0.05, min(1.0, float(v)))
        if abs(v - self._past_event_opacity) > 1e-6:
            self._past_event_opacity = v
            self._save()
            self.changed.emit()

    @Slot(float)
    def setHeroBlur(self, v: float) -> None:
        v = max(0.0, min(1.0, float(v)))
        if abs(v - self._hero_blur) > 1e-6:
            self._hero_blur = v
            self._save()
            self.changed.emit()

    @Slot(float)
    def setHeroDim(self, v: float) -> None:
        v = max(0.0, min(1.0, float(v)))
        if abs(v - self._hero_dim) > 1e-6:
            self._hero_dim = v
            self._save()
            self.changed.emit()

    @Slot(bool)
    def setShowEventImages(self, on: bool) -> None:
        if bool(on) != self._show_event_images:
            self._show_event_images = bool(on)
            self._save()
            self.changed.emit()

    @Slot(bool)
    def setTime24h(self, on: bool) -> None:
        if bool(on) != self._time_24h:
            self._time_24h = bool(on)
            self._save()
            self.changed.emit()

    @Slot(int)
    def setStartupTab(self, tab: int) -> None:
        tab = int(tab)
        if 0 <= tab <= 1 and tab != self._startup_tab:
            self._startup_tab = tab
            self._save()
            self.changed.emit()

    @Slot(str)
    def setDefaultView(self, view: str) -> None:
        if view in VIEW_IDS and view != self._default_view:
            self._default_view = view
            self._save()
            self.changed.emit()

    # Day-grid bounds are kept as a valid, non-empty range: start stays below
    # end and end above start (clamped against each other, not just 0..24).
    @Slot(int)
    def setDayStartHour(self, h: int) -> None:
        h = max(0, min(23, int(h)))
        h = min(h, self._day_end - 1)
        if h != self._day_start:
            self._day_start = h
            self._save()
            self.changed.emit()

    @Slot(int)
    def setDayEndHour(self, h: int) -> None:
        h = max(1, min(24, int(h)))
        h = max(h, self._day_start + 1)
        if h != self._day_end:
            self._day_end = h
            self._save()
            self.changed.emit()


class CalPrefs(QObject):
    """QML `CalPrefs` — per-calendar view overrides, persisted to calendars.json.

    Every map is calId → value; an absent key means "use the calendar's own":
      hidden       → true for hidden calendars (absent ⇒ visible)
      colors       → #rrggbb colour override (absent ⇒ the calendar's own colour)
      names        → display-name override (absent ⇒ the calendar's own name).
                     CalDAV can't be renamed server-side without a PROPPATCH, so
                     the override is a purely local relabel that works uniformly
                     for CalDAV, ICS and local calendars.
      descriptions → free-text note shown under the name in the sidebar.
      groups       → group label the calendar is filed under in the sidebar
                     (absent/"" ⇒ the ungrouped default section).
    All are QVariantMap properties so QML bindings recompute on every change.
    """

    changed = Signal()

    def __init__(self) -> None:
        super().__init__()
        self._hidden: dict = {}
        self._colors: dict = {}
        self._names: dict = {}
        self._descriptions: dict = {}
        self._groups: dict = {}
        self._load()

    @staticmethod
    def _str_map(raw) -> dict:
        return {str(k): v for k, v in (raw or {}).items()
                if isinstance(v, str) and v.strip()}

    def _load(self) -> None:
        try:
            data = json.loads(_config_path().read_text())
            self._hidden = {str(k): True
                            for k, v in (data.get("hidden") or {}).items() if v}
            self._colors = {str(k): v
                            for k, v in (data.get("colors") or {}).items()
                            if isinstance(v, str) and v.startswith("#")}
            self._names = self._str_map(data.get("names"))
            self._descriptions = self._str_map(data.get("descriptions"))
            self._groups = self._str_map(data.get("groups"))
        except (OSError, ValueError):
            # Separate dict literals — chained assignment would alias them all to
            # one dict, so a write to one map would leak into the others.
            self._hidden, self._colors = {}, {}
            self._names, self._descriptions, self._groups = {}, {}, {}

    def _save(self) -> None:
        path = _config_path()
        tmp = path.with_name(path.name + ".tmp")
        tmp.write_text(json.dumps(
            {"hidden": self._hidden, "colors": self._colors, "names": self._names,
             "descriptions": self._descriptions, "groups": self._groups}, indent=2))
        tmp.replace(path)

    # ── QML API ─────────────────────────────────────────────────────────────
    @Property("QVariantMap", notify=changed)
    def hidden(self):                       # noqa: D102
        return self._hidden

    @Property("QVariantMap", notify=changed)
    def colors(self):                       # noqa: D102
        return self._colors

    @Property("QVariantMap", notify=changed)
    def names(self):                        # noqa: D102
        return self._names

    @Property("QVariantMap", notify=changed)
    def descriptions(self):                 # noqa: D102
        return self._descriptions

    @Property("QVariantMap", notify=changed)
    def groups(self):                       # noqa: D102
        return self._groups

    @Slot(str)
    def toggleHidden(self, cal_id: str) -> None:
        if self._hidden.get(cal_id):
            self._hidden.pop(cal_id, None)
        else:
            self._hidden[cal_id] = True
        self._save()
        self.changed.emit()

    @Slot(str, str)
    def setColor(self, cal_id: str, hex_color: str) -> None:
        hex_color = (hex_color or "").strip()
        if hex_color.startswith("#"):
            self._colors[cal_id] = hex_color
        else:
            self._colors.pop(cal_id, None)   # empty ⇒ reset to the default colour
        self._save()
        self.changed.emit()

    @staticmethod
    def _set_in(m: dict, cal_id: str, value: str) -> None:
        value = (value or "").strip()
        if value:
            m[cal_id] = value
        else:
            m.pop(cal_id, None)              # empty ⇒ drop the override

    @Slot(str, str)
    def setName(self, cal_id: str, name: str) -> None:
        self._set_in(self._names, cal_id, name)
        self._save()
        self.changed.emit()

    @Slot(str, str)
    def setDescription(self, cal_id: str, text: str) -> None:
        self._set_in(self._descriptions, cal_id, text)
        self._save()
        self.changed.emit()

    @Slot(str, str)
    def setGroup(self, cal_id: str, group: str) -> None:
        self._set_in(self._groups, cal_id, group)
        self._save()
        self.changed.emit()

    # One-shot apply of the whole edit form (name/colour/description/group) so
    # the dialog persists in a single write + notify instead of four.
    @Slot(str, "QVariant")
    def apply(self, cal_id: str, patch) -> None:
        # A `{ … }` literal built in QML arrives as a QJSValue under PySide6, not
        # an auto-converted dict — dict() on it raises and aborts the caller's
        # Save handler mid-way (the dialog then never closes / nothing persists).
        if isinstance(patch, QJSValue):
            patch = patch.toVariant()
        p = dict(patch or {})
        if "color" in p:
            c = (p.get("color") or "").strip()
            if c.startswith("#"):
                self._colors[cal_id] = c
            else:
                self._colors.pop(cal_id, None)
        if "name" in p:
            self._set_in(self._names, cal_id, p.get("name") or "")
        if "description" in p:
            self._set_in(self._descriptions, cal_id, p.get("description") or "")
        if "group" in p:
            self._set_in(self._groups, cal_id, p.get("group") or "")
        self._save()
        self.changed.emit()

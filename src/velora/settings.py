"""Local per-calendar view preferences for velora.

velora deliberately keeps its own calendar visibility + colour overrides
separate from the shell — the app ignores the shell's caldav_hidden (see the
merge spec in todomodel). Preferences live in a flat JSON map at
$XDG_CONFIG_HOME/velora/calendars.json so they survive restarts and stay
hand-editable. Written atomically (tmp + replace).
"""

import json
import os
from pathlib import Path

from PySide6.QtCore import Property, QObject, Signal, Slot


def _config_dir() -> Path:
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    d = Path(base) / "velora"
    d.mkdir(parents=True, exist_ok=True)
    return d


def _config_path() -> Path:
    return _config_dir() / "calendars.json"


# Themes velora can pin instead of following wallust. "auto" ⇒ live wallust
# palette (see theme.py THEMES for the pinned palettes).
THEME_IDS = ["auto", "gruvbox", "dracula", "nord", "catppuccin", "tokyonight"]


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

    def _save(self) -> None:
        path = self._path()
        tmp = path.with_name(path.name + ".tmp")
        tmp.write_text(json.dumps(
            {"firstDayOfWeek": self._first_dow, "theme": self._theme,
             "pastEventOpacity": self._past_event_opacity}, indent=2))
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


class CalPrefs(QObject):
    """QML `CalPrefs` — per-calendar hidden flag + colour override, persisted.

    `hidden` maps calId → true for every hidden calendar (absent ⇒ visible).
    `colors` maps calId → #rrggbb override (absent ⇒ the calendar's own colour).
    Both are QVariantMap properties so QML bindings recompute on every change.
    """

    changed = Signal()

    def __init__(self) -> None:
        super().__init__()
        self._hidden: dict = {}
        self._colors: dict = {}
        self._load()

    def _load(self) -> None:
        try:
            data = json.loads(_config_path().read_text())
            self._hidden = {str(k): True
                            for k, v in (data.get("hidden") or {}).items() if v}
            self._colors = {str(k): v
                            for k, v in (data.get("colors") or {}).items()
                            if isinstance(v, str) and v.startswith("#")}
        except (OSError, ValueError):
            self._hidden, self._colors = {}, {}

    def _save(self) -> None:
        path = _config_path()
        tmp = path.with_name(path.name + ".tmp")
        tmp.write_text(json.dumps({"hidden": self._hidden, "colors": self._colors},
                                  indent=2))
        tmp.replace(path)

    # ── QML API ─────────────────────────────────────────────────────────────
    @Property("QVariantMap", notify=changed)
    def hidden(self):                       # noqa: D102
        return self._hidden

    @Property("QVariantMap", notify=changed)
    def colors(self):                       # noqa: D102
        return self._colors

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

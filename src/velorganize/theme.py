"""Live velumeron theming for the app.

Watches the wallust-rendered palette ($VELUMERON_USER_DIR/quickshell/colors.json,
flat keys background/foreground/color0..15) and the user's ui_font
(gui/settings.json). Semantic aliases mirror velumeron's quickshell/Colors.qml —
accent is color3 (bgActive). Both files are written atomically (tmp+replace),
which drops plain file watches, so the parent DIRECTORIES are watched too and
paths get re-added after every change, debounced to one reload.
"""

import json
import os
from pathlib import Path

from PySide6.QtCore import Property, QFileSystemWatcher, QObject, QTimer, Signal

_FALLBACK = {   # baked dark palette for a shell-less start
    "background": "#101014", "foreground": "#d6d6e0",
    **{f"color{i}": c for i, c in enumerate([
        "#16161c", "#22222c", "#2a2a36", "#5a5af0", "#3c3c50", "#44445a",
        "#7878e0", "#c8c8d4", "#70707e", "#8080f0", "#9090e8", "#a0a0f0",
        "#b0b0f8", "#e06c75", "#c0c0ff", "#f0f0fa"])},
}

# A regular sans for text (user feedback: not the mono Nerd Font everywhere) —
# ui_font from settings.json still wins. Icon glyphs (PUA) resolve through
# fontconfig's fallback to the installed Symbols Nerd Font.
_DEFAULT_FONT = "Noto Sans"
_ICON_FONT = "FantasqueSansM Nerd Font"


def _mix(a: str, b: str, t: float) -> str:
    """Blend two #rrggbb colors: a*(1-t) + b*t."""
    try:
        av = [int(a[i:i + 2], 16) for i in (1, 3, 5)]
        bv = [int(b[i:i + 2], 16) for i in (1, 3, 5)]
        return "#" + "".join(f"{round(x + (y - x) * t):02x}" for x, y in zip(av, bv))
    except (ValueError, IndexError):
        return a


def user_dir() -> Path:
    u = os.environ.get("VELUMERON_USER_DIR")
    if u:
        return Path(u)
    xdg = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return Path(xdg) / "velumeron"


class ThemeBridge(QObject):
    """QML context property `Theme` — color roles + fontFamily, live-updating."""

    themeChanged = Signal()

    def __init__(self) -> None:
        super().__init__()
        self._colors_path = user_dir() / "quickshell" / "colors.json"
        self._settings_path = user_dir() / "gui" / "settings.json"
        self._palette: dict = dict(_FALLBACK)
        self._font: str = _DEFAULT_FONT

        self._watcher = QFileSystemWatcher()
        self._debounce = QTimer(singleShot=True, interval=100)
        self._debounce.timeout.connect(self._reload)
        self._watcher.fileChanged.connect(lambda _p: self._poke())
        self._watcher.directoryChanged.connect(lambda _p: self._poke())
        self._rewatch()
        self._reload()

    # ── watching ──────────────────────────────────────────────────────────
    def _poke(self) -> None:
        self._rewatch()
        self._debounce.start()

    def _rewatch(self) -> None:
        paths = []
        for p in (self._colors_path, self._settings_path):
            if p.exists():
                paths.append(str(p))
            if p.parent.exists():
                paths.append(str(p.parent))
        old = self._watcher.files() + self._watcher.directories()
        if old:
            self._watcher.removePaths(old)
        if paths:
            self._watcher.addPaths(paths)

    # ── loading ───────────────────────────────────────────────────────────
    def _reload(self) -> None:
        palette = dict(_FALLBACK)
        try:
            data = json.loads(self._colors_path.read_text())
            for k in palette:
                v = data.get(k)
                if isinstance(v, str) and v.startswith("#"):
                    palette[k] = v
        except (OSError, ValueError):
            pass
        font = _DEFAULT_FONT
        try:
            v = json.loads(self._settings_path.read_text()).get("ui_font")
            if isinstance(v, str) and v.strip():
                font = v.strip()
        except (OSError, ValueError):
            pass
        if palette != self._palette or font != self._font:
            self._palette, self._font = palette, font
            self.themeChanged.emit()

    # ── QML API (aliases mirror quickshell/Colors.qml; accent = bgActive) ──
    def _get(self, key: str) -> str:
        return self._palette.get(key, _FALLBACK[key])

    @Property(str, notify=themeChanged)
    def fontFamily(self) -> str:            # noqa: D102
        return self._font

    @Property(str, notify=themeChanged)
    def iconFont(self) -> str:              # noqa: D102
        return _ICON_FONT

    # Softened surfaces — wallust's color0 can be near-pure black, which reads
    # far too harsh as an opaque window background (user feedback). Lift it
    # toward bgElement instead of using it raw.
    @Property(str, notify=themeChanged)
    def windowBg(self) -> str:              # noqa: D102
        return _mix(self._get("color0"), self._get("color1"), 0.30)

    @Property(str, notify=themeChanged)
    def surface(self) -> str:               # noqa: D102
        return _mix(self._get("color0"), self._get("color1"), 0.55)

    @Property(str, notify=themeChanged)
    def background(self) -> str:            # noqa: D102
        return self._get("background")

    @Property(str, notify=themeChanged)
    def foreground(self) -> str:            # noqa: D102
        return self._get("foreground")

    @Property(str, notify=themeChanged)
    def bgPrimary(self) -> str:             # noqa: D102
        return self._get("color0")

    @Property(str, notify=themeChanged)
    def bgElement(self) -> str:             # noqa: D102
        return self._get("color1")

    @Property(str, notify=themeChanged)
    def bgSecondary(self) -> str:           # noqa: D102
        return self._get("color2")

    @Property(str, notify=themeChanged)
    def bgActive(self) -> str:              # noqa: D102
        return self._get("color3")

    @Property(str, notify=themeChanged)
    def accent(self) -> str:                # noqa: D102
        return self._get("color3")

    @Property(str, notify=themeChanged)
    def bgHover(self) -> str:               # noqa: D102
        return self._get("color4")

    @Property(str, notify=themeChanged)
    def boNormal(self) -> str:              # noqa: D102
        return self._get("color5")

    @Property(str, notify=themeChanged)
    def boActive(self) -> str:              # noqa: D102
        return self._get("color6")

    @Property(str, notify=themeChanged)
    def fgPrimary(self) -> str:             # noqa: D102
        return self._get("color7")

    @Property(str, notify=themeChanged)
    def fgMuted(self) -> str:               # noqa: D102
        return self._get("color8")

    @Property(str, notify=themeChanged)
    def fgUrgent(self) -> str:              # noqa: D102
        return self._get("color13")

    @Property(str, notify=themeChanged)
    def fgBright(self) -> str:              # noqa: D102
        return self._get("color15")

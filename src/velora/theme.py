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

def _palette(bg, fg, colors):
    return {"background": bg, "foreground": fg,
            **{f"color{i}": c for i, c in enumerate(colors)}}


_FALLBACK = _palette(   # baked dark palette for a shell-less start
    "#101014", "#d6d6e0", [
        "#16161c", "#22222c", "#2a2a36", "#5a5af0", "#3c3c50", "#44445a",
        "#7878e0", "#c8c8d4", "#70707e", "#8080f0", "#9090e8", "#a0a0f0",
        "#b0b0f8", "#e06c75", "#c0c0ff", "#f0f0fa"])

# Pinned palettes for the fixed-theme option (Settings → Theme). Slots follow
# velumeron's semantic mapping, NOT ANSI: color0/1 = surfaces, color3 = accent,
# color5/6 = borders, color7 = text, color8 = muted, color13 = urgent, color15 =
# bright. (So a preset's signature accent lands in color3, its red in color13.)
THEMES = {
    "gruvbox": _palette("#1d2021", "#ebdbb2", [
        "#1d2021", "#282828", "#3c3836", "#fe8019", "#504945", "#3c3836",
        "#504945", "#ebdbb2", "#a89984", "#fb4934", "#b8bb26", "#fabd2f",
        "#83a598", "#fb4934", "#8ec07c", "#fbf1c7"]),
    "dracula": _palette("#282a36", "#f8f8f2", [
        "#282a36", "#2d2f3b", "#343746", "#bd93f9", "#44475a", "#3a3d4d",
        "#44475a", "#f8f8f2", "#6272a4", "#ff5555", "#50fa7b", "#f1fa8c",
        "#8be9fd", "#ff5555", "#ff79c6", "#ffffff"]),
    "nord": _palette("#2e3440", "#d8dee9", [
        "#2e3440", "#333b49", "#3b4252", "#88c0d0", "#434c5e", "#3b4252",
        "#4c566a", "#d8dee9", "#7b88a1", "#bf616a", "#a3be8c", "#ebcb8b",
        "#81a1c1", "#bf616a", "#b48ead", "#eceff4"]),
    "catppuccin": _palette("#1e1e2e", "#cdd6f4", [
        "#1e1e2e", "#232336", "#313244", "#cba6f7", "#45475a", "#313244",
        "#45475a", "#cdd6f4", "#a6adc8", "#f38ba8", "#a6e3a1", "#f9e2af",
        "#89b4fa", "#f38ba8", "#f5c2e7", "#f5f5fa"]),
    "tokyonight": _palette("#1a1b26", "#c0caf5", [
        "#1a1b26", "#1f2130", "#292e42", "#7aa2f7", "#3b4261", "#292e42",
        "#3b4261", "#c0caf5", "#565f89", "#f7768e", "#9ece6a", "#e0af68",
        "#7aa2f7", "#f7768e", "#bb9af7", "#ffffff"]),
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

    def __init__(self, settings=None) -> None:
        super().__init__()
        self._colors_path = user_dir() / "quickshell" / "colors.json"
        self._settings_path = user_dir() / "gui" / "settings.json"
        self._palette: dict = dict(_FALLBACK)
        self._font: str = _DEFAULT_FONT
        self._colorful: bool = False   # gui/settings.json colorful_enabled + colorful_menus

        # velora's own theme choice: "auto" follows wallust, anything else
        # pins a palette from THEMES. Reload whenever that choice changes.
        self._settings = settings
        self._mode: str = settings.theme if settings is not None else "auto"
        if settings is not None:
            settings.changed.connect(self._on_mode_change)

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

    def _on_mode_change(self) -> None:
        mode = self._settings.theme if self._settings is not None else "auto"
        if mode != self._mode:
            self._mode = mode
            self._reload()

    # ── loading ───────────────────────────────────────────────────────────
    def _reload(self) -> None:
        if self._mode in THEMES:
            palette = dict(THEMES[self._mode])          # pinned — ignore wallust
        else:
            palette = dict(_FALLBACK)                    # "auto" — follow wallust
            try:
                data = json.loads(self._colors_path.read_text())
                for k in palette:
                    v = data.get(k)
                    if isinstance(v, str) and v.startswith("#"):
                        palette[k] = v
            except (OSError, ValueError):
                pass
        font = _DEFAULT_FONT
        colorful = False
        try:
            data = json.loads(self._settings_path.read_text())
            v = data.get("ui_font")
            if isinstance(v, str) and v.strip():
                font = v.strip()
            # Mirrors quickshell/VtlConfig.qml's menuColorful: colorful_enabled
            # (default false) AND colorful_menus (default true) — see _base().
            colorful = bool(data.get("colorful_enabled", False)) and bool(data.get("colorful_menus", True))
        except (OSError, ValueError):
            pass
        if palette != self._palette or font != self._font or colorful != self._colorful:
            self._palette, self._font, self._colorful = palette, font, colorful
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

    # Surfaces mirror velumeron's shell (quickshell Style.qml): every fill is an
    # accent tint over a dark base — Style.tint(accent, a) with cardFill≈0.06,
    # controlFill≈0.12, controlHover≈0.22. CORRECTED (an earlier version of this
    # comment claimed the bar's colour comes from blur-through-translucency and
    # made the whole window translucent to match — checked quickshell's actual
    # source and that's wrong): panels are opaque by design. quickshell/Style.qml's
    # panelColor() = mix(Colors.bgPrimary, Colors.bgActive, colorful ? 0.12 : 0)
    # — raw color0 alone (t=0) only applies with colourful menus OFF; this user's
    # (and apparently velumeron's default-on) config has them on, which is why
    # the shell's own panels read warmer/lighter than plain color0. Match that
    # exactly instead of a flat, too-dark raw color0.
    def _base(self) -> str:
        c0 = self._get("color0")
        return _mix(c0, self._get("color3"), 0.12) if self._colorful else c0

    def _over(self, a: float) -> str:
        """Accent tint at alpha `a` composited over the base (opaque equivalent
        of the shell's Style.tint(accent, a) surfaces)."""
        return _mix(self._base(), self._get("color3"), a)

    @Property(str, notify=themeChanged)
    def windowBg(self) -> str:              # noqa: D102 — page / panel base
        return self._base()

    @Property(str, notify=themeChanged)
    def surface(self) -> str:               # noqa: D102 — sidebar / distinct panes
        return self._over(0.05)

    @Property(str, notify=themeChanged)
    def background(self) -> str:            # noqa: D102
        return self._base()

    @Property(str, notify=themeChanged)
    def foreground(self) -> str:            # noqa: D102
        return self._get("foreground")

    @Property(str, notify=themeChanged)
    def bgPrimary(self) -> str:             # noqa: D102 — cards / cells / inputs (≈cardFill)
        return self._over(0.07)

    @Property(str, notify=themeChanged)
    def bgElement(self) -> str:             # noqa: D102 — rows / buttons (≈controlFill)
        return self._over(0.13)

    @Property(str, notify=themeChanged)
    def bgSecondary(self) -> str:           # noqa: D102 — hover (≈controlHover)
        return self._over(0.22)

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

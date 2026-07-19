"""Disponera — QML application entry point."""

import importlib.resources
import os
import sys

from PySide6.QtGui import QGuiApplication, QIcon
from PySide6.QtQml import QQmlApplicationEngine, qmlRegisterType

from .caldav import CalDavBridge
from .local import LocalStore
from .mdhighlight import MarkdownHighlighter
from .notes import NotesStore
from .settings import AppSettings, CalPrefs
from .theme import ThemeBridge
from .todomodel import TodoBridge


def main() -> int:
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
    app = QGuiApplication(sys.argv)
    app.setApplicationName("disponera")
    app.setApplicationDisplayName("Disponera")
    # Wayland app_id — hypr window rules and the .desktop StartupWMClass match on this.
    app.setDesktopFileName("disponera")
    # Launcher/taskbar icon. On Wayland the compositor resolves the icon from the
    # matching .desktop (Icon=disponera → hicolor/scalable/apps/disponera.svg);
    # this sets it explicitly too for X11 and other environments.
    app.setWindowIcon(QIcon.fromTheme("disponera"))

    # Live-markdown TextEdit highlighter — used by MarkdownField.qml.
    qmlRegisterType(MarkdownHighlighter, "Disponera", 1, 0, "MarkdownHighlighter")

    engine = QQmlApplicationEngine()
    settings = AppSettings()
    theme = ThemeBridge(settings)
    local = LocalStore()
    todo = TodoBridge(local)
    caldav = CalDavBridge()
    # One CalDAV sync feeds both surfaces: when CalDavBridge refreshes its cache,
    # the todo model re-reads the same file in-process — no second subprocess and
    # no second network sync of the 34 calendars.
    caldav.cacheChanged.connect(todo.reloadCaldav)
    notes = NotesStore()
    calprefs = CalPrefs()
    ctx = engine.rootContext()
    ctx.setContextProperty("Theme", theme)
    ctx.setContextProperty("Todo", todo)
    ctx.setContextProperty("CalDav", caldav)
    ctx.setContextProperty("Local", local)
    ctx.setContextProperty("Notes", notes)
    ctx.setContextProperty("CalPrefs", calprefs)
    ctx.setContextProperty("Settings", settings)

    # qml/ ships inside the package (pyproject package-data), so the installed
    # wheel finds it — not just a source-tree checkout.
    qml_dir = importlib.resources.files("disponera") / "qml"
    engine.load(str(qml_dir / "Main.qml"))
    if not engine.rootObjects():
        return 1
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())

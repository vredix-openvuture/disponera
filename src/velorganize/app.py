"""velorganize — QML application entry point."""

import importlib.resources
import os
import sys

from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine

from .caldav import CalDavBridge
from .notes import NotesStore
from .theme import ThemeBridge
from .todomodel import TodoBridge


def main() -> int:
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
    app = QGuiApplication(sys.argv)
    app.setApplicationName("velorganize")
    app.setApplicationDisplayName("velorganize")
    # Wayland app_id — hypr window rules and the .desktop StartupWMClass match on this.
    app.setDesktopFileName("velorganize")

    engine = QQmlApplicationEngine()
    theme = ThemeBridge()
    todo = TodoBridge()
    caldav = CalDavBridge()
    notes = NotesStore()
    ctx = engine.rootContext()
    ctx.setContextProperty("Theme", theme)
    ctx.setContextProperty("Todo", todo)
    ctx.setContextProperty("CalDav", caldav)
    ctx.setContextProperty("Notes", notes)

    # qml/ ships inside the package (pyproject package-data), so the installed
    # wheel finds it — not just a source-tree checkout.
    qml_dir = importlib.resources.files("velorganize") / "qml"
    engine.load(str(qml_dir / "Main.qml"))
    if not engine.rootObjects():
        return 1
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())

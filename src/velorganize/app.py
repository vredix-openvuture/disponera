"""velorganize — QML application entry point."""

import os
import sys
from pathlib import Path

from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine

from .caldav import CalDavBridge
from .notes import NotesStore

QML_DIR = Path(__file__).resolve().parent.parent.parent / "qml"


def main() -> int:
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
    app = QGuiApplication(sys.argv)
    app.setApplicationName("velorganize")

    engine = QQmlApplicationEngine()
    caldav = CalDavBridge()
    notes = NotesStore()
    engine.rootContext().setContextProperty("CalDav", caldav)
    engine.rootContext().setContextProperty("Notes", notes)
    engine.load(str(QML_DIR / "Main.qml"))
    if not engine.rootObjects():
        return 1
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())

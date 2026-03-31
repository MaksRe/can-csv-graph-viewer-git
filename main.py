import os
from pathlib import Path
import sys

# Цель блока в явной настройке DPI-aware режима до импорта Qt.
# Он снижает риск предупреждений SetProcessDpiAwarenessContext на Windows.
if os.name == "nt":
    os.environ.setdefault("QT_QPA_PLATFORM", "windows:dpiawareness=1")

from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuickControls2 import QQuickStyle

from backend import CsvTrendBackend


def main() -> int:
    """Создает приложение и связывает QML-интерфейс с backend для работы с CSV-графиками."""
    # Цель блока в принудительном выборе кросс-платформенного стиля.
    # Он нужен, чтобы кастомные background/contentItem у Controls применялись одинаково.
    QQuickStyle.setStyle("Fusion")

    app = QGuiApplication(sys.argv)
    engine = QQmlApplicationEngine()

    backend = CsvTrendBackend()
    engine.rootContext().setContextProperty('backend', backend)

    qml_path = Path(__file__).resolve().parent / 'qml' / 'Main.qml'
    engine.load(str(qml_path))

    if not engine.rootObjects():
        return 1
    return app.exec()


if __name__ == '__main__':
    raise SystemExit(main())
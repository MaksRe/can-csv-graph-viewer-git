from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
from typing import Any


def load_build_version(version_path: Path) -> dict[str, int]:
    """Читает текущую версию сборки из JSON-файла."""
    if not version_path.exists():
        return {"major": 1, "minor": 0, "build": 0}

    with version_path.open("r", encoding="utf-8") as version_file:
        data: dict[str, Any] = json.load(version_file)

    return {
        "major": int(data.get("major", 1)),
        "minor": int(data.get("minor", 0)),
        "build": int(data.get("build", 0)),
    }


def save_build_version(version_path: Path, version_data: dict[str, int]) -> None:
    """Сохраняет версию сборки в JSON-файл в кодировке UTF-8."""
    with version_path.open("w", encoding="utf-8") as version_file:
        json.dump(version_data, version_file, ensure_ascii=False, indent=2)
        version_file.write("\n")


def bump_build_version(version_data: dict[str, int]) -> dict[str, int]:
    """Увеличивает номер билда на единицу для нового выпуска."""
    next_version = dict(version_data)
    next_version["build"] = int(next_version.get("build", 0)) + 1
    return next_version


def format_version(version_data: dict[str, int]) -> str:
    """Преобразует структуру версии в строку формата major.minor.build."""
    major = int(version_data.get("major", 1))
    minor = int(version_data.get("minor", 0))
    build = int(version_data.get("build", 0))
    return f"{major}.{minor}.{build}"


def run_tests(project_root: Path) -> None:
    """Запускает тесты перед сборкой, чтобы не выпускать сломанную версию."""
    command = [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-v"]
    subprocess.run(command, cwd=project_root, check=True)


def run_pyinstaller(project_root: Path, version_text: str) -> None:
    """Запускает PyInstaller со spec-файлом и передает версию через окружение."""
    exe_name = f"can_csv_graph_viewer_qml_v{version_text}"
    env = dict(os.environ)
    env["APP_BUILD_VERSION"] = version_text
    env["APP_EXE_NAME"] = exe_name

    command = [sys.executable, "-m", "PyInstaller", "--noconfirm", "can_csv_graph_viewer_qml.spec"]
    subprocess.run(command, cwd=project_root, env=env, check=True)


def main() -> int:
    """Выполняет полный цикл сборки: тесты, инкремент версии и упаковку exe."""
    project_root = Path(__file__).resolve().parent
    version_path = project_root / "build_version.json"

    current_version = load_build_version(version_path)
    next_version = bump_build_version(current_version)
    version_text = format_version(next_version)

    print(f"[build] Запуск тестов перед сборкой...")
    run_tests(project_root)

    print(f"[build] Новая версия сборки: {version_text}")
    print(f"[build] Запуск PyInstaller...")
    run_pyinstaller(project_root, version_text)
    save_build_version(version_path, next_version)

    print(f"[build] Готово. Версия: {version_text}")
    print(f"[build] Ожидаемое имя exe: can_csv_graph_viewer_qml_v{version_text}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

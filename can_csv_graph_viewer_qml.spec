# -*- mode: python ; coding: utf-8 -*-

from pathlib import Path
import os

from PyInstaller.utils.hooks import collect_data_files, collect_submodules


project_root = Path(os.getcwd()).resolve()
app_version = os.environ.get("APP_BUILD_VERSION", "0.0.0")
exe_name = os.environ.get("APP_EXE_NAME", f"can_csv_graph_viewer_qml_v{app_version}")


hiddenimports = []
hiddenimports += collect_submodules("openpyxl")
hiddenimports += collect_submodules("et_xmlfile")

datas = [
    (str(project_root / "qml"), "qml"),
    (str(project_root / "README.md"), "."),
    (str(project_root / "build_version.json"), "."),
]
datas += collect_data_files("openpyxl", include_py_files=True)
datas += collect_data_files("et_xmlfile", include_py_files=True)


a = Analysis(
    [str(project_root / "main.py")],
    pathex=[str(project_root)],
    binaries=[],
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name=exe_name,
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name=exe_name,
)

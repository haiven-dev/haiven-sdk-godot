#!/usr/bin/env python3
"""Export Linux, Windows, and macOS players for haiven-sdk-godot.

Requires the standard Godot 4.5.1 editor (not the .NET build) and the matching
standard export templates installed for that editor. One Linux host can export
all three presets. macOS signing and notarization are off in export_presets.cfg,
and Windows resource editing is off, so this does not need rcedit, osslsigncode,
or an Apple certificate.

The players pack the GDScript addon plus export/main.tscn. They are not a .NET
player and not a game. Haiven.Godot.dll is produced by package_release.py.

Produces, in --out:

  haiven-sdk-godot-linux-x64-<version>.zip
  haiven-sdk-godot-windows-x64-<version>.zip
  haiven-sdk-godot-macos-<version>.zip    the zip Godot writes for the macOS preset
  SHA256SUMS

Standard library only. Python 3.9+.
"""

from __future__ import annotations

import argparse
import hashlib
import shutil
import subprocess
import zipfile
from pathlib import Path

from package_release import SEMVER, ZIP_EPOCH, fail, plugin_version

REPO = Path(__file__).resolve().parent.parent
EXPECTED_VERSION_PREFIX = "4.5.1."
# Godot still looks up the debug template when exporting a release preset.
TEMPLATE_FILES = (
    "linux_release.x86_64",
    "linux_debug.x86_64",
    "windows_release_x86_64.exe",
    "windows_debug_x86_64.exe",
    "macos.zip",
)


def godot_version(godot: str) -> str:
    out = subprocess.run(
        [godot, "--version"], check=True, capture_output=True, text=True
    )
    return out.stdout.strip()


def require_templates() -> None:
    root = Path.home() / ".local" / "share" / "godot" / "export_templates" / "4.5.1.stable"
    missing = [name for name in TEMPLATE_FILES if not (root / name).is_file()]
    if missing:
        fail(
            "Godot 4.5.1 export templates are incomplete at "
            f"{root} (missing {', '.join(missing)}). Install "
            "Godot_v4.5.1-stable_export_templates.tpz there."
        )


def write_zip(dest: Path, files: list[Path]) -> None:
    with zipfile.ZipFile(dest, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for source in sorted(files, key=lambda path: path.name):
            info = zipfile.ZipInfo(source.name, date_time=ZIP_EPOCH)
            info.compress_type = zipfile.ZIP_DEFLATED
            mode = 0o755 if source.stat().st_mode & 0o111 else 0o644
            info.external_attr = mode << 16
            zf.writestr(info, source.read_bytes())


def export_preset(godot: str, preset: str, dest: Path) -> None:
    if dest.exists():
        fail(f"export destination already exists: {dest}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        godot,
        "--headless",
        "--path",
        str(REPO),
        "--export-release",
        preset,
        str(dest),
    ]
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True)
    if not dest.is_file():
        fail(f"preset {preset!r} did not write {dest}")


def zip_exports(version: str, out: Path, directory: Path, name: str) -> Path:
    files = [path for path in directory.iterdir() if path.is_file()]
    if not files:
        fail(f"no files to zip in {directory}")
    dest = out / f"{name}-{version}.zip"
    write_zip(dest, files)
    return dest


def assert_pe_or_elf(path: Path, magic: bytes, label: str) -> None:
    blob = path.read_bytes()[:4]
    if not blob.startswith(magic):
        fail(f"{path.name} is not a {label} export (magic {blob!r})")


def assert_macos_zip(path: Path) -> None:
    with zipfile.ZipFile(path) as zf:
        names = zf.namelist()
    if not any(name.endswith("Contents/Info.plist") for name in names):
        fail(f"{path.name} has no macOS .app/Contents/Info.plist")


def write_sums(out: Path, assets: list[Path]) -> None:
    lines = []
    for asset in sorted(assets, key=lambda path: path.name):
        digest = hashlib.sha256(asset.read_bytes()).hexdigest()
        lines.append(f"{digest}  {asset.name}\n")
    (out / "SHA256SUMS").write_text("".join(lines), encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--version", help="release version without the leading v")
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--godot", required=True, help="Godot 4.5.1 editor binary")
    args = parser.parse_args()

    declared = plugin_version()
    version = args.version if args.version is not None else declared
    if not SEMVER.match(version):
        fail(f"version {version!r} is not semver")
    if version != declared:
        fail(
            f"version {version} does not match addons/haiven/plugin.cfg version {declared}"
        )

    godot = args.godot
    if shutil.which(godot) is None and not Path(godot).is_file():
        fail(f"godot editor not found: {godot}")
    reported = godot_version(godot)
    if not reported.startswith(EXPECTED_VERSION_PREFIX):
        fail(f"godot {reported!r} is not {EXPECTED_VERSION_PREFIX}*")
    require_templates()

    out = args.out.resolve()
    if out.exists() and any(out.iterdir()):
        fail(f"output directory {out} is not empty")
    out.mkdir(parents=True, exist_ok=True)
    work = out / ".export"
    work.mkdir()

    linux_bin = work / "linux" / "haiven-sdk-godot.x86_64"
    windows_bin = work / "windows" / "haiven-sdk-godot.exe"
    macos_zip = work / "macos" / f"haiven-sdk-godot-macos-{version}.zip"
    export_preset(godot, "Linux", linux_bin)
    export_preset(godot, "Windows Desktop", windows_bin)
    export_preset(godot, "macOS", macos_zip)

    assert_pe_or_elf(linux_bin, b"\x7fELF", "Linux")
    assert_pe_or_elf(windows_bin, b"MZ", "Windows")
    assert_macos_zip(macos_zip)

    assets = [
        zip_exports(version, out, linux_bin.parent, "haiven-sdk-godot-linux-x64"),
        zip_exports(version, out, windows_bin.parent, "haiven-sdk-godot-windows-x64"),
        macos_zip,
    ]
    # Godot already wrote the macOS zip inside the work directory. Ship that
    # file from --out, next to the other archives.
    published_macos = out / macos_zip.name
    shutil.move(str(macos_zip), published_macos)
    assets[2] = published_macos
    shutil.rmtree(work)

    write_sums(out, assets)
    for path in sorted(out.iterdir()):
        print(f"{path.stat().st_size:>10}  {path.name}")


if __name__ == "__main__":
    main()

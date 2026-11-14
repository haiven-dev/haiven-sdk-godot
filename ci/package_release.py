#!/usr/bin/env python3
"""Build the haiven-sdk-godot release assets.

Produces, in --out:

  haiven-godot-addon-<version>.zip   addons/haiven/ (git-tracked files only),
                                     laid out to unzip into a Godot project root
  haiven-godot-dotnet-<version>.zip  Haiven.Godot.dll + Haiven.Sdk.Core.dll
                                     (and their .pdb/.xml when produced) from
                                     `dotnet build -c Release Haiven.Godot.csproj`
  SHA256SUMS                         sha256sum-compatible digests of both zips

The version must equal addons/haiven/plugin.cfg's `version`; the script fails
otherwise, so a tag cannot publish assets that report a different version.

The `X-Haiven-SDK: godot/<version>` header in
addons/haiven/haiven_http_transport.gd must carry the same version and end with
the `# x-release-please-version` marker that lets the release pull request bump
it; the script fails otherwise, so a lost marker cannot ship a stale header.

Haiven.Godot.csproj references ../haiven-sdk-unity/core/Haiven.Sdk.Core.csproj,
which in turn compiles ../../haiven-sdk-dotnet/Haiven.Sdk/*.cs. Those paths are
relative to sibling checkouts, so the build copies the three inputs into a
throwaway workspace with that sibling layout instead of building in place.
Pass the checkouts with --sdk-unity and --sdk-dotnet.

Standard library only; runs on Linux, macOS, and Windows with Python 3.9+.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PLUGIN_CFG = REPO / "addons" / "haiven" / "plugin.cfg"
TRANSPORT = REPO / "addons" / "haiven" / "haiven_http_transport.gd"
# The one line that sends the SDK version. release-please's Generic updater
# rewrites the first version on a line only when the line carries the marker.
SDK_HEADER = re.compile(r'"X-Haiven-SDK: godot/([^"]*)"')
RELEASE_MARKER = re.compile(r"#\s*x-release-please-version\s*$")
CSPROJ = "Haiven.Godot.csproj"
SEMVER = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$"
)
# Fixed zip timestamp (the zip format's earliest date) so the archives depend
# only on file contents and paths.
ZIP_EPOCH = (1980, 1, 1, 0, 0, 0)
# Assemblies that are ours to ship. GodotSharp and System.Text.Json come from
# the engine and the runtime respectively and are deliberately left out.
SHIPPED_ASSEMBLIES = ("Haiven.Godot", "Haiven.Sdk.Core")
SHIPPED_SUFFIXES = (".dll", ".pdb", ".xml")


def fail(message: str) -> "NoReturn":  # type: ignore[name-defined]
    print(f"package_release: error: {message}", file=sys.stderr)
    sys.exit(1)


def plugin_version() -> str:
    match = re.search(
        r'^\s*version\s*=\s*"([^"]*)"\s*$', PLUGIN_CFG.read_text("utf-8"), re.M
    )
    if not match:
        fail(f"no version= line in {PLUGIN_CFG.relative_to(REPO)}")
    return match.group(1)


def check_sdk_header(declared: str) -> None:
    """Fail unless the X-Haiven-SDK header matches plugin.cfg and stays release-managed."""
    rel = TRANSPORT.relative_to(REPO).as_posix()
    lines = [
        (number, line)
        for number, line in enumerate(TRANSPORT.read_text("utf-8").splitlines(), 1)
        if SDK_HEADER.search(line)
    ]
    if len(lines) != 1:
        fail(
            f"expected exactly one \"X-Haiven-SDK: godot/<version>\" line in {rel}, "
            f"found {len(lines)}"
        )
    number, line = lines[0]
    header = SDK_HEADER.search(line).group(1)
    if not RELEASE_MARKER.search(line):
        fail(
            f"{rel}:{number}: the X-Haiven-SDK header line must end with "
            f"`# x-release-please-version`; without it the release pull request "
            f"leaves the header at godot/{header}"
        )
    if header != declared:
        fail(
            f"{rel}:{number}: X-Haiven-SDK header version {header} does not match "
            f"addons/haiven/plugin.cfg version {declared}; the release pull request "
            f"bumps both together, so set the header to godot/{declared}"
        )


def tracked_files(repo: Path, *pathspecs: str) -> list[str]:
    out = subprocess.run(
        ["git", "-C", str(repo), "ls-files", "-z", "--", *pathspecs],
        check=True,
        capture_output=True,
    ).stdout.decode("utf-8")
    return sorted(p for p in out.split("\0") if p)


def head_commit() -> str:
    return subprocess.run(
        ["git", "-C", str(REPO), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()


def write_zip(dest: Path, entries: list[tuple[str, Path]]) -> None:
    """Write entries (arcname, source) in sorted order with fixed metadata."""
    with zipfile.ZipFile(dest, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for arcname, source in sorted(entries):
            info = zipfile.ZipInfo(arcname, date_time=ZIP_EPOCH)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            zf.writestr(info, source.read_bytes())


def build_addon_zip(version: str, out: Path) -> Path:
    files = tracked_files(REPO, "addons/haiven")
    if not files:
        fail("git ls-files found nothing under addons/haiven")
    dest = out / f"haiven-godot-addon-{version}.zip"
    write_zip(dest, [(f, REPO / f) for f in files])
    return dest


def stage_workspace(ws: Path, sdk_unity: Path, sdk_dotnet: Path) -> Path:
    """Recreate the sibling-checkout layout the csproj references expect."""
    godot = ws / "haiven-sdk-godot"
    for rel in tracked_files(REPO):
        if rel.endswith(".cs") or rel == CSPROJ:
            target = godot / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(REPO / rel, target)

    core_csproj = sdk_unity / "core" / "Haiven.Sdk.Core.csproj"
    if not core_csproj.is_file():
        fail(f"{core_csproj} not found; is --sdk-unity a haiven-sdk-unity checkout?")
    (ws / "haiven-sdk-unity" / "core").mkdir(parents=True)
    shutil.copy2(core_csproj, ws / "haiven-sdk-unity" / "core" / core_csproj.name)

    core_sources = sorted((sdk_dotnet / "Haiven.Sdk").glob("*.cs"))
    if not core_sources:
        fail(f"no {sdk_dotnet}/Haiven.Sdk/*.cs; is --sdk-dotnet a haiven-sdk-dotnet checkout?")
    (ws / "haiven-sdk-dotnet" / "Haiven.Sdk").mkdir(parents=True)
    for src in core_sources:
        shutil.copy2(src, ws / "haiven-sdk-dotnet" / "Haiven.Sdk" / src.name)
    return godot / CSPROJ


def build_dotnet_zip(
    version: str, out: Path, sdk_unity: Path, sdk_dotnet: Path, keep: Path | None
) -> Path:
    dotnet = shutil.which("dotnet")
    if not dotnet:
        fail("dotnet not found on PATH (pass --skip-dotnet to build only the addon zip)")
    ws = Path(tempfile.mkdtemp(prefix="haiven-godot-release-", dir=keep))
    try:
        csproj = stage_workspace(ws, sdk_unity.resolve(), sdk_dotnet.resolve())
        bin_dir = ws / "bin"
        cmd = [
            dotnet, "build", str(csproj),
            "-c", "Release",
            "-o", str(bin_dir),
            "-nologo",
            f"-p:Version={version}",
            "-p:ContinuousIntegrationBuild=true",
            "-p:Deterministic=true",
            # The staged workspace path is random; map it so the .pdb files do
            # not embed it, and stamp this repository's commit explicitly
            # instead of letting SourceLink discover whatever git repository
            # happens to enclose the workspace.
            f"-p:PathMap={ws}=/_/",
            "-p:EnableSourceControlManagerQueries=false",
            f"-p:SourceRevisionId={head_commit()}",
        ]
        print("+", " ".join(cmd), flush=True)
        subprocess.run(cmd, check=True)

        entries = [
            (p.name, p)
            for p in sorted(bin_dir.iterdir())
            if p.stem in SHIPPED_ASSEMBLIES and p.suffix in SHIPPED_SUFFIXES
        ]
        for name in SHIPPED_ASSEMBLIES:
            if not (bin_dir / f"{name}.dll").is_file():
                fail(f"build produced no {name}.dll in {bin_dir}")
        dest = out / f"haiven-godot-dotnet-{version}.zip"
        write_zip(dest, entries)
        return dest
    finally:
        if keep is None:
            shutil.rmtree(ws, ignore_errors=True)


def write_sums(out: Path, assets: list[Path]) -> Path:
    lines = []
    for asset in sorted(assets, key=lambda p: p.name):
        digest = hashlib.sha256(asset.read_bytes()).hexdigest()
        lines.append(f"{digest}  {asset.name}\n")
    dest = out / "SHA256SUMS"
    dest.write_text("".join(lines), encoding="utf-8", newline="\n")
    return dest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument(
        "--version",
        help="release version without the leading v (default: plugin.cfg's version)",
    )
    parser.add_argument("--out", type=Path, required=True, help="output directory")
    parser.add_argument("--sdk-unity", type=Path, help="haiven-sdk-unity checkout")
    parser.add_argument("--sdk-dotnet", type=Path, help="haiven-sdk-dotnet checkout")
    parser.add_argument(
        "--skip-dotnet", action="store_true", help="build only the addon zip"
    )
    parser.add_argument(
        "--keep-workspace",
        type=Path,
        help="create the staged build workspace under this directory and keep it",
    )
    args = parser.parse_args()

    declared = plugin_version()
    check_sdk_header(declared)
    version = args.version if args.version is not None else declared
    if not SEMVER.match(version):
        fail(f"version {version!r} is not semver (expected e.g. 1.2.3 or 1.2.3-rc.1)")
    if version != declared:
        fail(
            f"version {version} does not match addons/haiven/plugin.cfg version "
            f"{declared}; release tags come from merging the release-please release "
            f"pull request, which sets plugin.cfg to the tagged version"
        )

    out = args.out.resolve()
    if out.exists() and any(out.iterdir()):
        fail(f"output directory {out} is not empty")
    out.mkdir(parents=True, exist_ok=True)

    assets = [build_addon_zip(version, out)]
    if not args.skip_dotnet:
        if not args.sdk_unity or not args.sdk_dotnet:
            fail("--sdk-unity and --sdk-dotnet are required unless --skip-dotnet")
        if args.keep_workspace:
            args.keep_workspace.mkdir(parents=True, exist_ok=True)
        assets.append(
            build_dotnet_zip(
                version, out, args.sdk_unity, args.sdk_dotnet, args.keep_workspace
            )
        )
    write_sums(out, assets)
    for path in sorted(out.iterdir()):
        print(f"{path.stat().st_size:>10}  {path.name}")


if __name__ == "__main__":
    main()

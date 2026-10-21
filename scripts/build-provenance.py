#!/usr/bin/env python3
"""Allowlisted build provenance and signed-binary receipts. Never records env/paths/diffs."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import uuid


INPUTS = ("Package.swift", "Package.resolved", "Sources", "host/main.swift",
          "packaging/Info.plist", "packaging/lproj", "packaging/build-app.sh", "scripts/build-provenance.py")


def git(repo, *args):
    result = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, check=False)
    return result.stdout if result.returncode == 0 else None


def source_state(repo):
    raw = git(repo, "ls-files", "-z", "--cached", "--", *INPUTS)
    tracked = set() if raw is None else set(raw.decode("utf-8").split("\0")) - {""}
    # SwiftPM can compile ignored files too. Hash actual files, not just git's visible set;
    # keep tracked missing paths so deletions also change the fingerprint.
    files = set(tracked)
    for relative in INPUTS:
        path = repo / relative
        if path.is_symlink() or path.is_file():
            files.add(relative)
        elif path.is_dir():
            files.update(p.relative_to(repo).as_posix() for p in path.rglob("*") if p.is_file() or p.is_symlink())
    digest = hashlib.sha256()
    for relative in sorted(files):
        path = repo / relative
        digest.update(relative.encode("utf-8") + b"\0")
        if path.is_symlink():
            raise ValueError("Build inputs must not be symlinks")
        if path.is_file():
            digest.update(b"executable\0" if path.stat().st_mode & 0o111 else b"file\0")
            digest.update(hashlib.sha256(path.read_bytes()).digest())
        else:
            digest.update(b"missing\0")
    status = git(repo, "status", "--porcelain", "--untracked-files=all", "--", *INPUTS)
    flags = git(repo, "ls-files", "-v", "-z", "--cached", "--", *INPUTS)
    # Porcelain deliberately hides assume-unchanged/skip-worktree edits. Conservatively
    # mark these inputs dirty even when unchanged, rather than asserting a false clean build.
    index_hidden = flags is not None and any(entry.startswith(b"S ") or entry[:1].islower()
                                             for entry in flags.split(b"\0") if entry)
    dirty = None if status is None or raw is None or flags is None else bool(status.strip() or files - tracked or index_hidden)
    return digest.hexdigest(), dirty


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8") as output:
        json.dump(data, output, indent=2, sort_keys=True)
        output.write("\n")


def prepare(repo, plist, output, signing):
    with plist.open("rb") as handle:
        info = plistlib.load(handle)
    fingerprint, dirty = source_state(repo)
    revision = (git(repo, "rev-parse", "HEAD") or b"").decode().strip()
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", revision):
        revision = "unknown"
    version = subprocess.run(["swift", "--version"], capture_output=True, text=True, check=True)
    match = re.search(r"Swift version ([0-9]+(?:\.[0-9]+){0,3})", version.stdout)
    swift_version = match.group(1) if match else "unknown"
    app_version, build_number = str(info["CFBundleShortVersionString"]), str(info["CFBundleVersion"])
    if not re.fullmatch(r"[0-9]{1,6}(?:\.[0-9]{1,6}){0,3}", app_version) or not re.fullmatch(r"[0-9]{1,20}", build_number):
        raise ValueError("App version and build number must be numeric")
    # Host architecture is not proof of the produced artifact's architecture; finalize checks Mach-O.
    build = {"schema_version": 1, "app_version": app_version,
             "build_number": build_number, "build_id": str(uuid.uuid4()),
             "commit": revision, "source_dirty": dirty, "source_fingerprint": fingerprint,
             "built_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
             "configuration": "release", "architecture": "unknown", "swift_version": swift_version,
             "signing": signing}
    write_json(output, build)


def stamp(metadata, app):
    build = json.loads(metadata.read_text(encoding="utf-8"))
    architectures = subprocess.run(["lipo", "-archs", str(app / "Contents/MacOS/Beamhop")],
                                   capture_output=True, text=True, check=True).stdout.split()
    build["architecture"] = (architectures[0] if len(architectures) == 1 and architectures[0] in ("arm64", "x86_64")
                             else "universal" if set(architectures) == {"arm64", "x86_64"} else "unknown")
    write_json(app / "Contents/Resources/build-info.json", build)


def finalize(repo, app, output):
    build = json.loads((app / "Contents/Resources/build-info.json").read_text(encoding="utf-8"))
    fingerprint, dirty = source_state(repo)
    if fingerprint != build["source_fingerprint"] or dirty != build["source_dirty"]:
        raise ValueError("Build inputs changed during packaging; retry with stable inputs")
    artifacts = {}
    for name in ("Beamhop", "BeamhopMCP", "beamhop-bridge"):
        artifacts[name] = {"sha256": hashlib.sha256((app / "Contents/MacOS" / name).read_bytes()).hexdigest()}
    write_json(output, {"schema_version": 1, "build": build, "artifacts": artifacts,
                        "verification": "codesign --verify --deep --strict passed; not evidence of notarization or device acceptance"})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("prepare")
    p.add_argument("--repo", type=Path, required=True)
    p.add_argument("--plist", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--signing", choices=("adhoc", "identity"), required=True)
    p = sub.add_parser("stamp")
    p.add_argument("--metadata", type=Path, required=True)
    p.add_argument("--app", type=Path, required=True)
    p = sub.add_parser("finalize")
    p.add_argument("--repo", type=Path, required=True)
    p.add_argument("--app", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    args = vars(parser.parse_args())
    command = args.pop("command")
    {"prepare": prepare, "stamp": stamp, "finalize": finalize}[command](**args)


if __name__ == "__main__":
    main()

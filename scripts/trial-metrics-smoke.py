#!/usr/bin/env python3
"""Headless trial reporting: explicit temporary databases, no real Inbox/config."""
import argparse
import hashlib
from pathlib import Path
import sqlite3
import subprocess
import tempfile


def run(binary, *arguments):
    return subprocess.run([str(binary), *map(str, arguments)], capture_output=True,
                          text=True, timeout=30, check=False)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True, type=Path)
    binary = parser.parse_args().binary.resolve()
    with tempfile.TemporaryDirectory(prefix="beamhop-trial-cli-") as folder:
        folder = Path(folder)
        missing = folder / "missing.sqlite"
        assert run(binary, "--dogfood", missing).returncode == 2
        assert not missing.exists()
        database = folder / "fixture.sqlite"
        seed = run(binary, "--seed-hop", database)
        assert seed.returncode == 0, seed.stderr
        report = run(binary, "--dogfood", database, "--days", 7)
        assert report.returncode == 0, report.stderr
        assert "Attempts 2: copied 2" in report.stdout, report.stdout
        assert "not task completion" in report.stdout
        for private in ("never-export-original", "unselected body", "/private/fixture/"):
            assert private not in report.stdout
        for invalid in ("0", "-1", "banana", "99999999999999999999999999999"):
            rejected = run(binary, "--dogfood", database, "--days", invalid)
            assert rejected.returncode == 2, invalid
        legacy = folder / "pre-upgrade.sqlite"
        with sqlite3.connect(legacy) as connection:
            connection.execute("CREATE TABLE captures(id TEXT PRIMARY KEY)")
        before = hashlib.sha256(legacy.read_bytes()).hexdigest()
        result = run(binary, "--dogfood", legacy)
        assert result.returncode == 2
        assert "never creates or migrates" in result.stderr
        assert hashlib.sha256(legacy.read_bytes()).hexdigest() == before
    print("PASS: trial report separates receipts, excludes private text, rejects invalid windows, and never creates/migrates Inbox")


if __name__ == "__main__":
    main()

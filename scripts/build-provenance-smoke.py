"""Provenance regression tests with temporary repositories; no signing, app launch or user data."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("provenance", Path(__file__).with_name("build-provenance.py"))
PROVENANCE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PROVENANCE)


class ProvenanceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="beamhop-build-test-")
        self.addCleanup(self.directory.cleanup)
        self.repo = Path(self.directory.name)
        (self.repo / "Sources").mkdir()
        (self.repo / "Sources/main.swift").write_text("print(1)")
        self.plist = self.repo / "packaging/Info.plist"
        self.plist.parent.mkdir()
        self.plist.write_bytes(plistlib.dumps({"CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1"}))
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True)
        self.git("add", ".")
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "fixture")

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.repo), *args], check=True, capture_output=True)

    def prepare(self):
        path = self.repo / "metadata.json"
        original = subprocess.run
        with patch.object(PROVENANCE.subprocess, "run", wraps=subprocess.run) as run:
            run.side_effect = lambda args, **kwargs: (subprocess.CompletedProcess(args, 0, "Apple Swift version 6.4.0", "")
                                                       if args[0] == "swift" else original(args, **kwargs))
            PROVENANCE.prepare(self.repo, self.plist, path, "adhoc")
        return path

    def app(self, metadata):
        app = self.repo / "output/Beamhop.app"
        (app / "Contents/MacOS").mkdir(parents=True)
        (app / "Contents/Resources").mkdir()
        for name in ("Beamhop", "BeamhopMCP", "beamhop-bridge"):
            (app / "Contents/MacOS" / name).write_bytes(name.encode())
        with patch.object(PROVENANCE.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "arm64", "")):
            PROVENANCE.stamp(metadata, app)
        return app

    def test_clean_dirty_untracked_and_private_files(self):
        first, dirty = PROVENANCE.source_state(self.repo)
        self.assertFalse(dirty)
        (self.repo / ".mimosa").mkdir()
        (self.repo / ".mimosa/private.txt").write_text("SECRET token and /Users/private")
        (self.repo / "README.md").write_text("Documentation is not a build input")
        self.assertEqual(PROVENANCE.source_state(self.repo), (first, False))
        (self.repo / "Sources/main.swift").write_text("print(2)")
        changed, dirty = PROVENANCE.source_state(self.repo)
        self.assertTrue(dirty)
        self.assertNotEqual(first, changed)
        (self.repo / "Sources/new.swift").write_text("print(3)")
        self.assertNotEqual(changed, PROVENANCE.source_state(self.repo)[0])

    def test_receipt_contains_signed_bytes_and_allowlisted_metadata(self):
        metadata = self.prepare()
        app = self.app(metadata)
        output = self.repo / "receipt.json"
        PROVENANCE.finalize(self.repo, app, output)
        data = json.loads(output.read_text())
        self.assertEqual(data["artifacts"]["Beamhop"]["sha256"], hashlib.sha256(b"Beamhop").hexdigest())
        self.assertEqual(data["build"]["architecture"], "arm64")
        self.assertFalse(data["build"]["source_dirty"])
        for secret in (str(self.repo), os.path.expanduser("~"), "fixture@example.invalid", "Fixture"):
            self.assertNotIn(secret, output.read_text())
        with self.assertRaises(FileExistsError):
            PROVENANCE.finalize(self.repo, app, output)

    def test_source_changes_abort_record(self):
        metadata = self.prepare()
        app = self.app(metadata)
        (self.repo / "Sources/main.swift").write_text("changed during build")
        with self.assertRaisesRegex(ValueError, "Build inputs changed"):
            PROVENANCE.finalize(self.repo, app, self.repo / "receipt.json")
        self.assertFalse((self.repo / "receipt.json").exists())

    def test_missing_git_is_unknown_not_clean(self):
        archive = self.repo / "archive"
        archive.mkdir()
        with patch.object(PROVENANCE, "git", return_value=None):
            self.assertIsNone(PROVENANCE.source_state(archive)[1])

    def test_version_rejects_arbitrary_text(self):
        self.plist.write_bytes(plistlib.dumps({"CFBundleShortVersionString": "/Users/secret", "CFBundleVersion": "1"}))
        with self.assertRaises(ValueError):
            self.prepare()

    def test_symlink_is_rejected(self):
        (self.repo / "Sources/link.swift").symlink_to(self.repo / "README.md")
        with self.assertRaisesRegex(ValueError, "symlinks"):
            PROVENANCE.source_state(self.repo)

    def test_ignored_compilable_files_still_affect_provenance(self):
        first, dirty = PROVENANCE.source_state(self.repo)
        self.assertFalse(dirty)
        (self.repo / ".gitignore").write_text("*.generated.swift\n")
        (self.repo / "Sources/private.generated.swift").write_text("print(42)")
        second, dirty = PROVENANCE.source_state(self.repo)
        self.assertTrue(dirty)
        self.assertNotEqual(first, second)


if __name__ == "__main__":
    unittest.main()

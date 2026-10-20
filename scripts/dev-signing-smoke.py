"""Exercise signing password handling with command stubs; never touch a keychain."""

from pathlib import Path
import os
import secrets
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
SHELL = sys.argv[1] if len(sys.argv) > 1 else shutil.which("bash")
if not SHELL:
    raise SystemExit("bash is required")


def run_case(name, script, supplied, expected_exit, *, fail_unlock=False, fail_sign=False):
    with tempfile.TemporaryDirectory(prefix="beamhop-signing-test-") as directory:
        sandbox = Path(directory)
        tools = sandbox / "tools"
        tools.mkdir()
        calls = sandbox / "calls"
        calls.touch()
        for relative in ("scripts/setup-dev-signing.sh", "packaging/build-app.sh"):
            target = sandbox / relative
            target.parent.mkdir(exist_ok=True)
            target.write_bytes((ROOT / relative).read_text(encoding="utf-8").encode("utf-8"))
        for relative in (".build/release/Beamhop", ".build/release/BeamhopMCP", "packaging/Info.plist"):
            target = sandbox / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("fixture", encoding="utf-8")
        (sandbox / ".build/resources/Beamhop_Beamhop.bundle").mkdir(parents=True)
        mocks = {
            "uname": "echo Darwin\n",
            "swift": "exit 0\n",
            "swiftc": 'touch "$4"\n',
            "plutil": "exit 0\n",
            "security": '''
test -z "${BEAMHOP_KEYCHAIN_PASSWORD+x}" || exit 90
printf '%s\n' "$1" >> "$SIGNING_TEST_CALLS"
case "$1" in
  create-keychain|unlock-keychain)
    test "$3" = "$SIGNING_TEST_EXPECTED" || exit 91
    if test "$1" = unlock-keychain && test "$SIGNING_TEST_FAIL_UNLOCK" = 1; then exit 92; fi
    ;;
  set-key-partition-list) test "$6" = "$SIGNING_TEST_EXPECTED" || exit 93 ;;
  find-certificate) echo 'SHA-1: fixture-certificate' ;;
esac
''',
            "codesign": '''
test -z "${BEAMHOP_KEYCHAIN_PASSWORD+x}" || exit 90
echo codesign >> "$SIGNING_TEST_CALLS"
test "$SIGNING_TEST_FAIL_SIGN" != 1
''',
        }
        for command, body in mocks.items():
            path = tools / command
            path.write_bytes(("#!/bin/sh\n" + body).encode("utf-8"))
            path.chmod(0o755)
        fixture = secrets.token_hex(24)
        env = os.environ.copy()
        for key in ("BEAMHOP_KEYCHAIN_PASSWORD", "BEAMHOP_CODESIGN_IDENTITY", "BEAMHOP_CODESIGN_KEYCHAIN"):
            env.pop(key, None)
        env.update({
            "PATH": str(tools) + os.pathsep + env.get("PATH", ""),
            "SIGNING_TEST_CALLS": str(calls),
            "SIGNING_TEST_EXPECTED": fixture,
            "SIGNING_TEST_FAIL_UNLOCK": "1" if fail_unlock else "0",
            "SIGNING_TEST_FAIL_SIGN": "1" if fail_sign else "0",
        })
        if supplied is not None:
            env["BEAMHOP_KEYCHAIN_PASSWORD"] = fixture if supplied else ""
        if script.startswith("packaging"):
            env["BEAMHOP_CODESIGN_IDENTITY"] = "Beamhop Fixture"
            env["BEAMHOP_CODESIGN_KEYCHAIN"] = str(sandbox / "fixture.keychain")
        result = subprocess.run([SHELL, "-x", script], cwd=sandbox, env=env,
                                stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
        # Never include command output in a failing assertion: it could contain the fixture.
        assert fixture not in result.stdout + result.stderr, name + ": password appeared in trace"
        assert result.returncode == expected_exit, f"{name}: exit {result.returncode}, expected {expected_exit}"
        operations = calls.read_text(encoding="utf-8").splitlines()
        if script.startswith("scripts") and expected_exit != 0:
            assert not operations, name + ": touched keychain without a password"
        if script.startswith("packaging"):
            assert ("unlock-keychain" in operations) == bool(supplied), name + ": unexpected unlock"
            assert ("codesign" in operations) != fail_unlock, name + ": signed after unlock failure"
        print("PASS", name)


run_case("setup requires a secret before keychain access", "scripts/setup-dev-signing.sh", None, 2)
run_case("setup rejects an empty secret", "scripts/setup-dev-signing.sh", False, 2)
run_case("setup accepts a supplied secret without logging or exporting it", "scripts/setup-dev-signing.sh", True, 0)
run_case("packaging can use an already unlocked keychain", "packaging/build-app.sh", None, 0)
run_case("packaging unlocks with a supplied secret", "packaging/build-app.sh", True, 0)
run_case("unlock failure prevents signing", "packaging/build-app.sh", True, 5, fail_unlock=True)
run_case("signing failure is not downgraded to ad-hoc signing", "packaging/build-app.sh", None, 5, fail_sign=True)

#!/usr/bin/env python3
"""Actual stdio regression. Explicit temporary databases only; no app registration."""
import argparse
import json
from pathlib import Path
import sqlite3
import subprocess
import tempfile


def rpc(binary, database, requests):
    process = subprocess.run([str(binary), "--db", str(database)],
                             input="".join(json.dumps(request) + "\n" for request in requests),
                             text=True, capture_output=True, timeout=30, check=True)
    return {row["id"]: row for row in map(json.loads, process.stdout.splitlines())}


def call(number, name, arguments):
    return {"jsonrpc": "2.0", "id": number, "method": "tools/call",
            "params": {"name": name, "arguments": arguments}}


def payload(response):
    assert "error" not in response, response
    result = response["result"]
    assert not result.get("isError"), result
    return json.loads(result["content"][0]["text"])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mcp-binary", required=True, type=Path)
    parser.add_argument("--seed-binary", required=True, type=Path)
    args = parser.parse_args()
    binary = args.mcp_binary.resolve()
    seed_binary = args.seed_binary.resolve()
    with tempfile.TemporaryDirectory(prefix="beamhop-hop-protocol-") as directory:
        path = Path(directory) / "fixture.sqlite"
        listing = rpc(binary, path, [{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}])
        names = {tool["name"] for tool in listing[1]["result"]["tools"]}
        assert {"fetch_handoff", "save_handoff_result", "fetch_handoff_results",
                "fetch_capture", "save_result", "fetch_results", "search_captures"} <= names, names
        missing = rpc(binary, path, [call(1, "fetch_handoff", {"handoff_id": "missing"}),
                                     call(2, "save_handoff_result", {"handoff_id": "missing", "agent": "fixture", "content": "no"})])
        assert all(row["result"].get("isError") for row in missing.values())
        assert not path.exists(), "MCP must not create a missing database"
        seed = subprocess.run([str(seed_binary), "--seed-hop", str(path)],
                              capture_output=True, text=True, timeout=30, check=True)
        fixture = json.loads(seed.stdout)
        origin = fixture["enabled"]
        content = "结论 <>&\nLiteral answer"
        responses = rpc(binary, path, [
            call(1, "fetch_handoff", {"handoff_id": origin}),
            call(2, "save_handoff_result", {"handoff_id": origin, "agent": "fixture-agent", "content": content, "session_id": "fixture-session"}),
            call(3, "fetch_handoff_results", {"handoff_id": origin}),
            call(4, "save_handoff_result", {"handoff_id": fixture["disabled"], "agent": "fixture", "content": "reject"}),
            call(5, "save_handoff_result", {"handoff_id": "unknown", "agent": "fixture", "content": "reject"}),
            call(6, "save_handoff_result", {"handoff_id": origin, "agent": "  ", "content": "reject"}),
            call(7, "save_handoff_result", {"handoff_id": origin, "agent": "fixture", "content": " \n"}),
            call(8, "fetch_handoff", {"handoff_id": fixture["disabled"]}),
            call(9, "fetch_handoff_results", {"handoff_id": "unknown"}),
            call(10, "fetch_capture", {"id": fixture["capture"]}),
            call(11, "save_result", {"origin_capture_id": fixture["capture"], "agent": "legacy", "content": "legacy conclusion"}),
            call(12, "fetch_results", {"origin_capture_id": fixture["capture"]}),
            call(13, "fetch_handoff", {}),
            call(14, "fetch_handoff_results", {"handoff_id": origin, "limit": -1}),
            call(15, "fetch_handoff_results", {"handoff_id": origin, "limit": 1e100}),
            call(16, "fetch_handoff", {"handoff_id": 42}),
        ])
        snapshot = payload(responses[1])
        assert snapshot["id"] == origin and snapshot["transportStatus"] == "copied"
        assert "edited snapshot" in snapshot["text"] and snapshot["text"].startswith("/review\nkeep literal")
        for secret in ("never-export-original", "unselected body", "/private/fixture/"):
            assert secret not in json.dumps(snapshot)
        saved = payload(responses[2])
        assert saved["content"] == content and saved["handoff_id"] == origin
        assert saved["session_id"] == "fixture-session"
        assert payload(responses[3]) == [saved]
        for number in (4, 5, 6, 7, 8, 9, 13, 16):
            assert responses[number]["result"].get("isError"), number
        assert payload(responses[10])["id"] == fixture["capture"]
        assert payload(responses[11])["content"] == "legacy conclusion"
        assert len(payload(responses[12])) == 1
        assert payload(responses[14]) == [saved]
        assert payload(responses[15]) == [saved]
        # A separate MCP process sees the same result; the copied receipt is unchanged.
        reopened = rpc(binary, path, [call(1, "fetch_handoff", {"handoff_id": origin}),
                                      call(2, "fetch_handoff_results", {"handoff_id": origin})])
        assert payload(reopened[1])["transportStatus"] == "copied"
        assert payload(reopened[2]) == [saved]
        # A legacy backup must not become returnable just because its draft has an opt-in flag.
        with sqlite3.connect(path) as connection:
            legacy = json.loads(connection.execute("SELECT payload FROM hop_records WHERE id = ?", (origin,)).fetchone()[0])
            legacy.pop("envelopeVersion")
            legacy["id"] = "legacy-fixture"
            connection.execute("INSERT INTO hop_records (id, payload) VALUES (?, ?)",
                               (legacy["id"], json.dumps(legacy).encode()))
        legacy_responses = rpc(binary, path, [call(1, "fetch_handoff", {"handoff_id": legacy["id"]}),
                                              call(2, "save_handoff_result", {"handoff_id": legacy["id"], "agent": "fixture", "content": "reject"})])
        assert all(row["result"].get("isError") for row in legacy_responses.values())
        # Simulate the pre-v10 schema in this disposable database, not a real Inbox.
        with sqlite3.connect(path) as connection:
            connection.execute("DROP TABLE handoff_results")
        old = rpc(binary, path, [call(1, "fetch_handoff", {"handoff_id": origin}),
                                 call(2, "save_handoff_result", {"handoff_id": origin, "agent": "fixture", "content": "reject"}),
                                 call(3, "fetch_capture", {"id": fixture["capture"]})])
        assert old[1]["result"].get("isError") and old[2]["result"].get("isError")
        assert payload(old[3])["id"] == fixture["capture"]
        with sqlite3.connect(path) as connection:
            assert not connection.execute("SELECT name FROM sqlite_master WHERE name = 'handoff_results'").fetchall()
    print("PASS: Hop MCP identity/privacy, optional save/fetch, invalid arguments, restart, legacy tools and no migrations")


if __name__ == "__main__":
    main()

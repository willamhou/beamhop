# S4 — Chrome Native Messaging

Status: **NOT RUN**

Use the production-shaped implementation under `browser-extension/` and `Sources/BeamhopNativeHost/`. First run its pure protocol tests, then load it unpacked in Chrome and record ten 900 KiB round trips.

| Browser/version | ping | 900 KiB | median | p95 | reconnect after host exit |
|---|---:|---:|---:|---:|---:|
| Chrome | not run | not run | not run | not run | not run |

- [ ] PASS — median < 100 ms and payload reassembled exactly
- [ ] FAIL — activate local HTTP fallback decision
- [x] NOT RUN


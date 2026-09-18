# Evidence — M2 offline release performance baseline

- Date/time and operator: 2026-09-15T23:02:58Z, automated local Codex session
- Exact repository commit SHA: `6fcb63e3c17db57eaf7f60c83fd18c63e25b3ab4`
- Related requirement and acceptance IDs: F07, M2-AC12
- Evidence level: I
- Status: PASS
- Environment: macOS 26.6.2 build 25G83, Apple Silicon MacBookPro18,3,
  arm64, Xcode 26.6 build 17F113, Swift 6.3.3
- Application path: release `label-driver validate`; offline CLI and private
  render worker, with no scheduler or browser path
- Printer/transport/stock: not applicable to this offline measurement; no
  printer or transport was accessed
- Fixture: `Fixtures/generated/native-vector.pdf`, SHA-256
  `24af4c33cd98b4373048c3fdf88085a1da098e7cebc97b147d051fd99ecf5c61`
- Job ticket: `Examples/offline-ticket-v1.json`, SHA-256
  `d6a74471a2e062f1c048a82c3eaa691914afd3452a2fab1d5fcc6535204df9d3`
- Hardware/installation authorization: not required; zero labels, zero device
  commands, and zero system changes

## Procedure

The committed harness was first validated with its unit tests. The release
executable was built outside the timed region, the worktree was confirmed clean,
and this command recorded one cold and twenty warm invocations:

```sh
swift build -c release --package-path Packages/LabelMac --product label-driver
python3 scripts/benchmark_offline.py --runs 20 \
  --output docs/validation/M2-PERFORMANCE-BASELINE-2026-09-15.json
```

Each iteration launched `/usr/bin/time -l label-driver validate` with the exact
fixture and ticket above. The harness required a prepared JSON result with
`printerIOPerformed=false`, checked stable dimensions/output bytes across all
runs, measured monotonic wall time, and captured the macOS-reported maximum RSS.
The first run followed the untimed release build; filesystem caches were not
purged. Warm runs were separate CLI/worker processes, not iterations inside one
long-lived process.

## Expected and observed results

The proposed engineering targets were warm p95 below 500 ms and peak processing
memory below 256 MiB for a simple 4×6 label. The observed prepared output was
813×1219 dots (991,047 pixels) and 248,814 ZPL bytes.

- Cold: 120.850 ms; 13,828,096 maximum resident bytes.
- Warm median: 118.812 ms.
- Warm p95 (nearest-rank, 20 runs): 123.138 ms.
- Warm range: 113.997–124.482 ms.
- Maximum warm resident bytes: 14,106,624.
- Conservative p95 throughput: 8,048,274 pixels/s and 2,020,614 prepared
  ZPL bytes/s.

Both proposed M2 engineering targets passed with the specified fixture and
environment. Output dimensions and byte count were identical in every run.

## Artifacts

- `docs/validation/M2-PERFORMANCE-BASELINE-2026-09-15.json` contains the raw
  warm samples, exact input/executable hashes, environment, summary, and scope.
- `scripts/benchmark_offline.py` is the reusable bounded harness.
- `scripts/tests/test_benchmark_offline.py` fixes the parser and nearest-rank
  percentile semantics.

## Limitations / next action

This proves an offline release render-and-encode baseline only. It does not
measure scheduler overhead, USB transfer, printer mechanics, first physical
label time, sustained physical rate, browser/application latency, or a clean-host
installation. `/usr/bin/time -l` supplies the command RSS value; no claim is
made that it decomposes parent and worker peaks. M6 must repeat this exact input
and harness before setting a release regression budget. Transport and physical
timings remain separately blocked on their prescribed evidence and consent.

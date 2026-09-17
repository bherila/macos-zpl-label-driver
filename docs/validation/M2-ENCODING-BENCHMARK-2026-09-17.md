# M2 — reproducible experimental graphic-encoding comparison

Additional M2.5 implementation and partial M2-AC07/12 evidence. The existing
render-and-encode baseline remains separate; this measures only encoding of
synthetic packed 813×1219 / 124338-byte input, with no transport/device access.

The nearest independent constraints are exact deterministic output and bounded
execution: measurements must retain the same full bytes on every iteration,
and the developer CLI may not accept an unbounded iteration count. It performs
one untimed warm-up, then 1-100 complete diagnostic encodes with monotonic timing;
byte equality checks run after each timed interval. Production selection and
prepared-job output remain plain hex. No firmware capability is inferred.

The Python reference driver uses the explicitly built release lab, three fixed
patterns and two encodings. macOS `/usr/bin/time -l` supplies whole-process peak
RSS. Portable accelerator checks all six one-iteration reports and six invalid
argument cases in debug/release. Three Python tests reject identity/schema,
boolean/overflow output and missing/nonfinite/oversized timing samples.

## Actual initial reference measurements

Apple Silicon MacBookPro18,3, macOS 27.0 (26A428), Xcode 27.0 / 27A266a,
Swift 6.4. Twenty timed iterations per encoding/pattern after warm-up.
[Raw report](M2-ENCODING-BENCHMARK-2026-09-17.json) records exact executable hash,
source head and `sourceDirty: true`: this is the uncommitted benchmark working
snapshot on top of the locally validated lease commit, not a claim of a clean
released build or hosted timing threshold.

| Pattern | Encoding | Output bytes | p95 encoding ms | Process peak RSS bytes |
|---|---|---:|---:|---:|
| white | plain | 248814 | 3.550 | 9732096 |
| white | ascii | 1365 | 0.248 | 8896512 |
| checker | plain | 248814 | 3.591 | 9682944 |
| checker | ascii | 5014 | 1.468 | 9027584 |
| analytic | plain | 248814 | 3.534 | 9404416 |
| analytic | ascii | 235491 | 45.358 | 9682944 |

White/repeated content shrinks sharply. The analytic input shrinks only about
5% and is roughly 13× slower to encode in this measurement. Do not select
compression blindly from model name or this benchmark; firmware qualification
and workload tradeoffs remain explicit. No regression budget is invented from
one run. RSS includes the bitmap, retained expected output and timed output;
it does not count allocations or isolate the encoder scratch buffer. Process
startup, bitmap generation and warm-up are excluded from encoding timings.

## Reproduction and gates

```sh
swift build --package-path Packages/LabelCore --configuration release
python3 scripts/benchmark_encoding.py --executable "$(swift build --package-path Packages/LabelCore --configuration release --show-bin-path)/label-core-lab" --iterations 20
```

- Explicit release build, twelve developer CLI checks and six reference cases:
  PASS, exit 0. Three focused Python tests: PASS, exit 0.
- Required `bash scripts/ci-swift.sh`: PASS, exit 0 within the 900-second
  timeout. 89 Python / 190 Core / 273 Mac tests pass in debug/release, both
  original 132 / compressed 180 oracle vectors and all twelve benchmark CLI
  checks per configuration, 15 inert ABI / 14 filter ABI / one discard pipeline,
  native builds, nested ad-hoc signatures, ARM/minimum-26 metadata and packaged
  worker PBM/ZPL equality.
- Hosted run 35200866409: PASS at exact preceding source 8c041aa, with retained
  log confirming native 269-test suites, both oracles and packaged-worker equality.
  It does not cover the later lease or benchmark source.
- PDF rendering/physical throughput, scheduler, USB and firmware: NOT RUN here.
  Compression remains off for the first physical proof. No merge or publication.

Next: complete gates, publish both coherent follow-ons on existing PR #81,
and retain changed-head hosted/manual evidence. No third cloud review request.

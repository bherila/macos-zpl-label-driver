# M2 — experimental ASCII compression short-run performance

Performance implementation follow-on to PR #81; additional M2.5 / partial
M2-AC07/12 evidence. This addresses the measured workload tradeoff without
changing enabled production encodings, command syntax, output bytes or limits.

The nearest independent constraint is exact literal/count token selection at
all boundaries: one/two digits must remain literal; three-plus digit runs use
the same additive documented count spelling. The row writer now appends short
literal runs directly and emits counts into the existing output buffer, avoiding
a temporary Data per run and a two-element nibble array per source byte. It does
not claim zero allocations or change per-band history, preflight or sink behavior.

Six focused compression tests pass before and after, exit 0. A new independent
set of explicit expected spellings covers the literal edge, lowercase/uppercase
counts and repeated 400-count tokens. This is a performance change rather than
a claim of an old correctness failure. The original plain oracle and independent
compressed oracle remain unchanged and are run by the full gate.

## Observed release comparison

Same Apple Silicon MacBookPro18,3, macOS27.0/26A428, Xcode27.0/27A266a,
Swift6.4; twenty timed iterations per pattern/encoding after warm-up. See the
[original report](M2-ENCODING-BENCHMARK-2026-09-17.json) and
[new raw report](M2-COMPRESSION-FASTPATH-2026-09-17.json). Source dirty flags and
exact executable hashes remain recorded rather than claiming clean release provenance.

| ASCII pattern | Earlier p95 ms | New p95 ms | Unchanged output bytes |
|---|---:|---:|---:|
| white | 0.248 | 0.241 | 1365 |
| checker | 1.468 | 0.631 | 5014 |
| analytic | 45.358 | 8.795 | 235491 |

Analytic compression is about five times faster in these samples. Its output is
still only about5% smaller than plain hex and encoding remains about2.4x slower
than the newly measured plain path. Repeated-row savings remain strong. These
are informational reference measurements, not CI thresholds or proof of a
universal speedup. Whole-process RSS is not allocation counting; unchanged
byte counts alone are not the bit-exact oracle. Deterministic full-output equality
is checked within each benchmark and both cross-language oracles remain required.

## Gates and next action

- Explicit release build and six twenty-iteration reference cases: PASS, exit0.
- Six focused compression tests: PASS before and after, exit0.
- Required `bash scripts/ci-swift.sh`: PASS, exit0 within the 900-second
  bound. 89 Python / 191 Core / 273 Mac tests pass in debug/release, unchanged
  original132/compressed180 oracle vectors and twelve benchmark CLI cases per
  configuration, 15 inert ABI/14filter ABI/one discard pipeline, native builds,
  nested ad-hoc signatures, ARM/minimum26 metadata and packaged-worker equality.
- Hosted preceding c3e03af run35202180091 remains active; later source is not covered.
- Firmware, actual device memory/performance, scheduler, USB and physical labels:
  NOT RUN. Ordinary prepared labels remain plain hex and first physical compression OFF.

Complete the required gate and let the preceding hosted run finish before
publishing. No third cloud review, merge or release. Frozen B candidate unchanged.

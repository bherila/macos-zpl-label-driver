# M3 prepared-job payload evidence — 2026-09-15

## Scope

Commit `acf11ab` adds a complete ordered prepared-job payload contract. One
typed encoder result is required for every resolved output label, in resolved
order. All labels must carry the same immutable printer-profile snapshot, every
label must be nonempty, and the complete concatenated printer-language payload
is bounded before allocation and append.

Direct public construction of a `PreparedLabel` is removed; public callers
obtain it through the typed production encoder. The job-level contract rejects
missing, extra, empty, mixed-profile, over-count, and over-budget label sets.
This contract prepares the exact bytes that a persistent lifecycle record can
hash and later authorize for delivery; it performs no transport operation.

## Validation performed

On Apple Silicon macOS 26.6.2 with Xcode 26.6:

- Prepared-label/job focused tests — 7 passed.
- Ordered two-label concatenation and exact label count — passed.
- Missing, extra, empty, mixed-profile, and aggregate-limit cases — rejected.
- `bash scripts/ci-swift.sh` — PASS.
- Repository preflight and fixture integrity — PASS.
- Python tests — 56 passed.
- LabelCore debug and release — 163 passed in each configuration.
- LabelMac debug and release — 101 passed in each configuration.
- Independent ZPL/PBM/analytic round trips — 132 passed.
- Inert CUPS backend ABI — 15 passed.
- Inert CUPS filter ABI — 10 passed.
- Inert filter-to-discard pipeline — 1 passed.
- Local ad-hoc command-line and setup-app signature checks — PASS.

## Acceptance impact and remaining gates

This adds partial automated evidence for M3-AC02, M3-AC09, and M5-AC07. No row
is newly complete. The job payload is not yet persisted beside the accepted
bundle or atomically linked to the `prepared` lifecycle generation. The real
multi-page extraction/render pipeline, scheduler intake, delivery mapping,
restart recovery, queue installation, transport, and physical printer remain
open.

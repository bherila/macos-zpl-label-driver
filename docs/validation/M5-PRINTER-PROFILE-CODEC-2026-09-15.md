# M5 canonical printer-profile codec evidence — 2026-09-15

## Scope

Commit `87c7e8c` adds an exact bounded private persistence contract for immutable
printer-profile snapshots. This is portable encoding/decoding and automated
test evidence only. It does not discover a printer, publish a queue, install a
component, elevate privileges, send a device command, or establish any new
hardware capability.

The version-1 format explicitly represents model capabilities and evidence,
installed accessories and read-only observations, media facts and calibration,
transport, and the private stable connection identity. Public descriptions of
that identity remain redacted. Tracking choices have fixed keys, speed choices
are deterministically sorted, nullable and unobserved states remain distinct,
and every object has an exact key set. Unknown fields, duplicate speeds,
malformed observation/evidence combinations, invalid internal evidence,
unsupported schemas, bad scalar types, and oversized input/output fail closed.

This format is private product configuration. It is not a public capability
claim or a replacement for per-model and per-installation evidence.

## Validation performed

On Apple Silicon macOS 26.6.2 with Xcode 26.6:

- `swift test --package-path Packages/LabelCore --filter PrinterProfileJSONTests`
  — 5 passed.
- `swift test --package-path Packages/LabelCore` — 141 passed.
- `bash scripts/ci-swift.sh` — PASS.
- Repository preflight and fixture integrity — PASS.
- Python tests — 56 passed.
- LabelCore debug and release — 141 passed in each configuration.
- LabelMac debug and release — 79 passed in each configuration.
- Independent ZPL/PBM/analytic round trips — 132 passed.
- Inert CUPS backend ABI — 15 passed.
- Inert CUPS filter ABI — 10 passed.
- Inert filter-to-discard pipeline — 1 passed.
- Local ad-hoc command-line and setup-app signature checks — PASS; unavailable
  Developer-ID selection continued to fail closed.

The focused suite round-trips the conservative GC420d reference and a fully
observed synthetic profile with raw-TCP identity, observations, and media
calibration. It also checks deterministic re-encoding and adversarial schema
rejection.

## Acceptance impact and remaining gates

This is additional partial automated support for M3-AC01, M3-AC13, M5-AC05,
and M5-AC07. No row is newly complete. A private immutable printer-profile
store must hash these canonical bytes and become the trusted resolver for queue
bindings. Discovery, installed profile creation, active revision selection,
scheduler publication, system-dialog defaults, restart recovery, USB delivery,
and physical acceptance remain unverified.

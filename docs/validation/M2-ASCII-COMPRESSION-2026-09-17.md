# M2 — experimental lossless ASCII graphic compression

## Slice and constraints

Branch: `codex/m2-ascii-graphic-compression`, stacked on PR #79.
Advances M2.5 and M2-AC07 automated implementation; firmware capability selection
and physical behavior remain unqualified. No global milestone is completed.

The independent constraint is that compression preserves the complete packed
bitmap and cannot carry previous-row history across a graphic field. Tests cover
non-byte-aligned white padding, count composition, forced bands, repeated rows,
literal fallback, exact total budget before sink callbacks, and immediate sink
failure propagation. Unknown/unsupported capability states fail before output.
The ordinary prepared-job path and its original plain-hex oracle are unchanged.
The new diagnostic envelope is offline-only and intentionally has no production
state normalization. It must not be connected directly to a printer.

## Protocol and implementation

R43 records public Zebra protocol provenance. ASCII repeat counts and previous-row
repetition are distinct from `^GFC`, Z64 and persistent graphic downloads. Count
metadata stays in decoded bytes. Each row falls back to literal hex when count
encoding would expand it. Scratch is bounded to one row (at most 8,000 ASCII bytes
under the encoder geometry cap). The writer preflights actual encoded size in a
first pass and streams rows in a second pass. No imaging or compression library
or third-party implementation is added.

The developer vector executable adds compressed counterparts for the existing
132 analytic bitmaps, plus 48 independently checked blank/black/nibble/checker
boundary cases. The separate Python decoder validates count expansion, framing,
row limits, padding, exact rows and field metadata. It rejects incomplete counts,
row overflow, unsupported symbols and cross-band repetition. The existing oracle
is not modified to agree with the new encoder. Ordinary CI runs both oracles in
debug and release.

## Validation

- Before implementation: debug accelerator passed, 82 Python / 180 Core tests,
  132 original round-trips, 15 probe / 14 filter / 1 inert pipeline cases.
- Focused: five Swift compression tests and four Python decoder tests passed.
- Full `bash scripts/ci-swift.sh`: exit 0, 86 Python / 185 Core / 264 Mac
  tests in debug and release, 132 original and 180 compressed independent
  vectors per configuration, both inert harnesses and pipeline, ARM/minimum-26
  signatures and packaged-worker PBM/ZPL equality. Local host: macOS 27.0
  (26A428), arm64, Xcode 27.0 (27A266a), Swift 6.4. This is noninteractive
  framework evidence on that runtime, not Tahoe/manual/physical acceptance.
- Hosted CI / independent review: NOT RUN until publication.
- Firmware compression support, administrator scheduler admission, GUI, USB,
  physical output, install lifecycle: NOT RUN. No new consent or support claim.

## Next action

Review and publish this slice after full local checks; keep first GC420d physical
proof uncompressed. Later production compression selection must bind firmware
qualification to the immutable profile rather than accept a model-name guess.

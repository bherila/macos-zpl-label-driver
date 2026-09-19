# Evidence — one-bit layout at M2-AC04's adversarial widths, and re-seal of M2-AC13

- Date/time and operator: 2026-09-19, automated Claude session, unattended
- Exact repository commit SHA: `8ab3429d4bd96db326cdd0ddaed44229f30c8100`
- Related requirement and acceptance IDs: M2-AC04 and M2-AC13. M2-AC04 maps to
  F06, which also needs M2-AC02, M2-AC03, M2-AC05, M2-AC11 and M6-AC05; M2-AC13
  maps to F20.
- Evidence level: A
- Status: PASS
- macOS/Linux, architecture, Swift, Xcode/SDK, runner image (as applicable):
  Linux x86_64 (`x86_64-unknown-linux-gnu`), Swift 6.1.2 release toolchain,
  CPython 3. No Xcode, no macOS runner.
- Application/version and system-dialog versus browser-preview path: portable
  `LabelCore` engine and the offline `label-core-lab` vector emitter only.
- Printer model, resolution, firmware family, transport, stock/accessories (no serial):
  none. No printer, transport or device command.
- Fixture ID/hash and generator version: no committed fixture corpus. The 132
  round-trip vectors are generated into a temporary directory at run time and
  discarded; their `vectors.json` manifest is schema version 1.
- Profile/job-ticket revision/hash: none read or written.
- Explicit hardware/installation authorization and finite label/command budget:
  not required and not requested. Zero labels, zero device commands, zero system
  changes.

## Procedure

This document exists for two reasons, and they are connected.

`M2-AC04` was unchecked during review of #102 because
`MonochromeConversion`'s `photographicOrderedDither4x4` branch packs rows itself
rather than delegating to `MonochromeBitmap.threshold`, and was exercised only at
widths 2 and 4 while the criterion names 1, 7, 8, 9, 811, 812 and 813. #105 added
those vectors. That was a LabelCore source change, which is why it could not also
record the evidence: `source_is_unchanged` treats any diff outside evidence
metadata, `docs/validation/*.md`, milestone `ACCEPTANCE.md` files and
`MANIFEST.sha256` as a source change, so the commit adding the tests
simultaneously invalidated `M2-AC13`'s record, which binds
`MonochromeBitmapTests.swift` among its evidence. Measured on `main` immediately
after #105 merged, the report read 0 criteria with `M2-AC13` at
`referencesValid: false, currentSource: false`.

So this slice records both: the new `M2-AC04` coverage, and `M2-AC13` re-bound to
the merge commit above. Executed with the Swift 6.1.2 toolchain on `PATH`:

```sh
python3 scripts/run-accelerator-checks.py
```

## Expected and observed results

The suite passed end to end (`exit 0`):

```
Executed 313 tests, with 0 failures (0 unexpected) in 4.291 seconds
Cross-language ZPL/PBM/analytic round-trips: 132
Independent ASCII compression round-trips: 180
Finite encoding benchmark CLI cases: 12
Inert CUPS ABI cases: 15
Inert CUPS filter ABI cases: 14
Inert filter-to-discard pipeline cases: 1
PASS: offline accelerator suite. macOS/scheduler/hardware qualification is separate.
```

`MonochromeBitmapTests` is 19 tests, up from 17.

For **M2-AC04**, two of those 19 are the new vectors.
`testPhotographicDitherAdversarialWidths` covers each width the criterion names,
at height 5 so `y & 3` wraps past the four-row Bayer screen. Pure black is below
every threshold the screen produces (the lowest is 8) and pure white above every
one (the highest is 248), which pins stride, MSB-first placement and the white
tail without re-deriving the screen; a third vector blacks only the first and last
column, so a packer shifting from the wrong end returns indices mirrored within
their byte. `testPhotographicDitherScreenPhaseHoldsAcrossByteBoundaries` uses
uniform mid gray at 813 dots, where row 0 ranks columns by `x & 3` as 0, 8, 2, 10,
so 128 is black exactly on the odd columns across the whole row — pinning the
screen phase against the column index rather than the byte offset. Both decode set
bits MSB-first and compare against an independently computed column set, rather
than asserting bytes the implementation could agree with by construction.

**The coverage is proven by mutation rather than asserted.** Replacing
`packed[y * layout.bytesPerRow + x / 8]` with `packed[y * layout.bytesPerRow]` —
always the row's first byte, identical for any width up to 8 — leaves all three
pre-existing dither tests green and fails both new ones, 41 assertions in total.
An LSB-first shift is caught as well, though `MonochromeBitmap.init` already
rejected that through its tail-padding guard, so that mutation demonstrates
nothing the ledger did not already have.

The record binds all three layout owners: `BitmapLayout` for stride,
`MonochromeBitmap` for the tail-padding guard and the threshold packer, and
`MonochromeConversion` for the dither packer.

For **M2-AC13** nothing new is claimed. The same run covers
`PhysicalGeometryTests.testGC420dPhysicalPitchOracle`, `BitmapLayoutTests`,
`MonochromeBitmapTests` and `ZPLGraphicEncoderTests` at the bytes the re-bound
record cites, and `scripts/tests/test_reference_target.py` exercises
`scripts/check_reference_target.py`, which derives the 813×1219 dimensions and
enforces the distinct 832-dot head extent, the unknown gap and liner values and
the nominal-DPI separation.

## Artifacts

No binary artifact is retained: the vector corpus is written to a temporary
directory and deleted by the harness, which also asserts that a second
`label-core-lab` run refuses to overwrite an existing destination. The counts
above are the whole observable result. Hosted CI evidence for the source change is
the green `ci-required`, `swift-macos-arm64` and `repository-preflight` on #105.

## Limitations / next action

Linux, Swift 6.1.2, evidence level A. This qualifies the portable one-bit layout
and the reference arithmetic. It does not qualify `QuartzPDFToMonochrome`, which
is how the dither packer is reached for a real page on macOS, and it touches none
of the eleven criteria waiting on #103. Core Graphics, LabelMac, macOS printing,
the scheduler, signing, USB, the GUI and any GC420d behaviour remain NOT RUN.

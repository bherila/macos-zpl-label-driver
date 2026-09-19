# Evidence — M2-AC04 and M2-AC13 re-sealed after the report-deadline change

- Date/time and operator: 2026-09-19, automated Claude session, unattended
- Exact repository commit SHA: `9527188af32226ab1f2117ed2d332980d4db8e0f`
- Related requirement and acceptance IDs: M2-AC04 and M2-AC13. M2-AC04 maps to
  F06, which also needs M2-AC02, M2-AC03, M2-AC05, M2-AC11 and M6-AC05; M2-AC13
  maps to F20, which also needs M0-AC11, M3-AC13, M4-AC13 and M6-AC13.
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

No new claim. This re-binds two existing records after a source change, which is
the third time this slice pattern has been needed and the reason it is now written
down as a rule rather than rediscovered.

#109 bounded `manifest_describes_tree` by one shared report deadline. It changed
`scripts/traceability_report.py` and its test, and `scripts/` is not among the
paths `source_is_unchanged` exempts, so both records stopped being current the
moment it merged. Measured on `main` at `9527188` before this slice:

```
criteria: []
   M2-AC04 valid True current False
   M2-AC13 valid True current False
```

`valid` stayed true because neither record cites a file #109 touched — only the
currency rule tripped. That distinction matters: the records were never wrong, they
simply stopped vouching for a tree they had not seen.

Executed with the Swift 6.1.2 toolchain on `PATH`:

```sh
python3 scripts/run-accelerator-checks.py
python3 -m unittest discover -s scripts/tests
python3 scripts/check_repo.py
```

## Expected and observed results

All passed:

```
Executed 313 tests, with 0 failures (0 unexpected) in 4.028 seconds
Cross-language ZPL/PBM/analytic round-trips: 132
Independent ASCII compression round-trips: 180
Finite encoding benchmark CLI cases: 12
Inert CUPS ABI cases: 15
Inert CUPS filter ABI cases: 14
Inert filter-to-discard pipeline cases: 1
PASS: offline accelerator suite. macOS/scheduler/hardware qualification is separate.
```

`python3 -m unittest discover -s scripts/tests` reports 108 tests, OK — three more
than the 105 before #109, which are its own regressions. `check_repo.py` passed.

This run exercises the changed reporting path as well as the records' own
evidence: `scripts/tests/test_traceability_report.py` is inside the 108, and the
report was then re-run on the committed tree to confirm both records read current.

For **M2-AC04** the cited suites are `BitmapLayoutTests` and
`MonochromeBitmapTests`, the latter carrying the two ordered-dither vectors added
by #105 at the widths the criterion names — 1, 7, 8, 9, 811, 812 and 813 — whose
coverage was proven by mutation before the record was first written. Its bound
owners remain `BitmapLayout` for stride, `MonochromeBitmap` for the tail-padding
guard and the threshold packer, and `MonochromeConversion` for the dither packer.

For **M2-AC13** the cited evidence is unchanged: `PhysicalGeometryTests`
(including `testGC420dPhysicalPitchOracle`, the only test driving the
implementation from 4×6 inches at 8 dots/mm), `BitmapLayoutTests`,
`MonochromeBitmapTests`, `ZPLGraphicEncoderTests`, and
`scripts/tests/test_reference_target.py` exercising
`scripts/check_reference_target.py`, which derives the 813×1219 dimensions and
enforces the distinct 832-dot head extent, the unknown gap and liner values and
the nominal-DPI separation.

Both records report no unbound implementation owner under the mechanical audit
(every top-level LabelCore type mapped to its declaring file, then each record
checked for files its cited tests reference but its `implementation` list omits).

## Artifacts

No binary artifact is retained: the vector corpus is written to a temporary
directory and deleted by the harness, which also asserts that a second
`label-core-lab` run refuses to overwrite an existing destination. Hosted CI
evidence for the source change is the green `ci-required`, `swift-macos-arm64` and
`repository-preflight` on #109.

## Limitations / next action

Linux, Swift 6.1.2, evidence level A. Two criteria out of ninety. Everything
asserting what the product emits, accepts or refuses still has an enforcement site
in LabelMac and cannot be closed from here — eleven criteria wait on one hosted
`macos-26` run, tracked in #103, including all three F04 needs. `QuartzPDFToMonochrome`
is how the dither packer is reached for a real page and is not covered. Core
Graphics, LabelMac, macOS printing, the scheduler, signing, USB, the GUI and any
GC420d behaviour remain NOT RUN.

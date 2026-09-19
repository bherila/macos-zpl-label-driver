# Evidence — execution run for every suite the M2/M3 ledger records cite

- Date/time and operator: 2026-09-18, automated Claude session, unattended
- Exact repository commit SHA: `78acd9bde132211e0af9fdba01b9795f5d98d35b`
- Related requirement and acceptance IDs: M2-AC13 — the only record remaining in
  `docs/ACCEPTANCE-EVIDENCE.json`. It maps to F20. M2-AC01, M2-AC04, M2-AC05,
  M2-AC06, M3-AC01, M3-AC02, M3-AC03 and M3-AC04 were all withdrawn during review
  of #102; see Limitations. This run
  contributes nothing to F07, which maps only to M2-AC07, M2-AC12 and M6-AC09.
- Evidence level: A
- Status: PASS
- macOS/Linux, architecture, Swift, Xcode/SDK, runner image (as applicable):
  Linux x86_64 (`x86_64-unknown-linux-gnu`), Swift 6.1.2 release toolchain,
  CPython 3. No Xcode, no macOS runner, no SDK-specific step.
- Application/version and system-dialog versus browser-preview path: portable
  `LabelCore` engine and the offline `label-core-lab` vector emitter only. No
  application, system print dialog or preview path was involved.
- Printer model, resolution, firmware family, transport, stock/accessories (no serial):
  none. No printer, transport or device command. GC420d geometry appears only as
  documented arithmetic.
- Fixture ID/hash and generator version: no committed fixture corpus is used. The
  132 round-trip vectors are generated into a temporary directory by
  `label-core-lab` at run time and discarded; their `vectors.json` manifest is
  schema version 1.
- Profile/job-ticket revision/hash: none read or written.
- Explicit hardware/installation authorization and finite label/command budget:
  not required and not requested. Zero labels, zero device commands, zero system
  changes.

## Procedure

This run exists because review of #102 found the M2-AC05/AC06/AC13 records cited
only Swift tests that never decode produced ZPL, and the M3-AC02/AC03 records
omitted suites that do cover the criteria. A later round found the remaining
records' only execution artifacts predate the bytes they now bind: M2-AC01 and
M2-AC04 cited a run at `3ad4bf0`, before the external-rectangle and
overflowing-corner admission changes landed, and M3-AC01 and M3-AC04 cited a
2026-09-17 per-ID assessment taken before the documented-control encoder grew
its darkness, thermal, tracking, dimension and offset paths. A digest proves
which source is present, not that it passed. This document is therefore the
current execution artifact for the remaining record, which is possible because
the command below runs the whole package, not a selected subset.

The following was executed with the Swift 6.1.2 toolchain on `PATH`:

```sh
python3 scripts/run-accelerator-checks.py
```

That harness runs repository and fixture preflight, every Python test under
`scripts/tests`, the full `LabelCore` test suite, then builds `label-core-lab`,
emits the vector corpus into a temporary directory and hands it to the
independent Python oracles for decoding.

The working tree at the time of the run is commit
`0c8d8c3d75991f7062cc01280b9b364ec0941a64`. Every file it changes relative to
the cited source SHA is documentation (`MANIFEST.sha256`,
`docs/ACCEPTANCE-EVIDENCE.json`, `docs/HANDOFF.md`, `docs/PROGRESS.json`,
`docs/milestones/03-printer-controls/ACCEPTANCE.md`); no Swift or Python source
differs, so the executed behaviour is the behaviour at the cited SHA.

## Expected and observed results

The suite passed end to end (`exit 0`), with these counted oracles:

```
Executed 311 tests, with 0 failures (0 unexpected) in 4.688 seconds
Cross-language ZPL/PBM/analytic round-trips: 132
Independent ASCII compression round-trips: 180
Finite encoding benchmark CLI cases: 12
Inert CUPS ABI cases: 15
Inert CUPS filter ABI cases: 14
Inert filter-to-discard pipeline cases: 1
PASS: offline accelerator suite. macOS/scheduler/hardware qualification is separate.
```

The oracle is not an assertion that the encoder agrees with itself. For each of
the 132 vectors, `scripts/zpl_oracle.py::verify_vectors` reads the Swift-emitted
`.pbm`, parses the Swift-emitted `.zpl` envelope, rejects unknown commands,
wrong `^GFA` counts, wrong `^FO` origins, non-zero row padding, trailing content
and second envelopes, then requires the decoded bytes to equal both the packed
PBM and an independently computed `analytic_bitmap(width, height)`, and the
per-band row counts to equal the manifest's `bandRows`. A missing, duplicated or
seam-shifted row changes the reconstruction and fails the comparison. That is
the byte-for-byte unpack/repack reconstruction M2-AC05 names, the multi-band
row/seam integrity M2-AC06 names, and the band reconstruction half of M2-AC13.
`scripts/zpl_compression_oracle.py` repeats the decode over the ASCII-compressed
form for 180 further vectors.

`scripts/tests/test_zpl_oracle.py` (13 cases) is the oracle's own guard: it
proves the decoder rejects each of those malformations rather than passing
anything handed to it, so a green `verify_vectors` is not vacuous.

For M3, `ZPLDocumentedControlEncoderTests` asserts the exact emitted byte
sequence for the documented control set —
`^PR3,4,2\n^MD0\n~SD07\n^MTD\n^MNM,-12\n^PW813\n^LH9,17\n^LS-23\n^LT31\n^MMT\n` —
covering speed, darkness, thermal method, tracking, dimensions, offsets and the
tear-off finishing mode in one ordered envelope, and separately proves every
`ZPLDocumentedControl.Kind` fails closed under `.unknown` and `.unsupported`.
That is the mapping M3-AC03 requires, as distinct from
`ZPLControlProtocolCoverageTests`, which only checks the static metadata table.
`ThermalControlQualificationTests` and `ThermalControlIntegrationTests` add the
thermal half of M3-AC02: each method requires compatible observed media and
ribbon, documentation cannot substitute for loaded configuration, unknown is not
false, and a higher-priority incompatible method is rejected rather than falling
back. `FinishingControlQualificationTests` and `FinishingJobPlanTests` add its
finishing half, which the tear-off GC420d baseline in `PrinterProfileTests`
cannot supply on its own because that baseline only ever *rejects* cut, peel and
rewind: the finishing suites carry the accepted-choice side — exact bytes per
mode, per-accessory installation observation that model documentation cannot
stand in for, cut schedules with an explicit remainder policy, per-mode stock
declarations that installed accessories do not waive, and malformed batch
declarations that must not turn unknown into unlimited.

M3-AC04 is withdrawn for the reason in Limitations. The relevant coverage is
recorded here anyway, because it is real and it will matter when that record is
rebuilt on a hosted run: `ZPLDocumentedControlEncoderTests` is the negative
coverage on the *current* LabelCore control paths:
`testAlternateDarknessAndThermalMappingHaveNoPersistentOrCopyCommands` asserts
the exact emitted text for darkness, thermal-transfer and gap-tracking
combinations and then asserts the absence of `^JU`, `~JC`, `~JA`, `^PQ`, `^MMC`,
`^MMP`, `^MNA` and `^MNV`, and further asserts that the ordinary reference
profile refuses to resolve darkness, tracking or thermal-method jobs at all. The
previously bound `ZPLControlEncoderTests` and `ZPLPreparedLabelEncoderTests`
carry the same family checks on the baseline and prepared-envelope paths, so the
three together cover the paths the record binds.

M2-AC06 has a profile-limit half distinct from its encoder-limit half: a profile
whose raster bounds are narrower than the generic 32,000-dot protocol ceiling
must still contain its fields. That enforcement is
`PhysicalGeometryQualification.validateRaster` and `ZPLPreparedLabelEncoder`,
with `PhysicalGeometryQualificationTests` and `ZPLPreparedLabelEncoderTests`,
now bound. M3-AC01's truthfulness claim ranges over every capability domain, not
only the base profile and finishing, so `PrinterControlResolution`,
`PhysicalGeometryQualification`, `OffsetControlQualification` and
`ThermalControlQualification` are bound with `MotorSpeedIntegrationTests`,
`PhysicalGeometryQualificationTests`, `OffsetControlQualificationTests` and
`ThermalControlQualificationTests`. Running the whole package does not make an
unbound file evidence for a criterion; the binding has to be explicit, which is
the correction here.

For M2-AC01 and M2-AC04 no new claim is made. `PDFPageGeometryTests`,
`PhysicalGeometryTests`, `BitmapLayoutTests` and `MonochromeBitmapTests` ran here
as part of the 311, at the bytes the records bind, which is what those records
were missing.

## Artifacts

No binary artifact is retained: the vector corpus is written to a temporary
directory and deleted by the harness, which also asserts that a second
`label-core-lab` run refuses to overwrite an existing destination. The counts
above are the whole observable result. The corresponding CI evidence is the
`ci-required` check on this branch's head.

## Limitations / next action

**M3-AC03 is withdrawn, and F04 with it.** The criterion requires the protocol
mapping to cover supported finishing. `FinishingControlQualification` emits
`^MMT`, `^MMC`, `^MMP` and `^MMR` for bounded offline inspection and says in its
own comment that `^MMC` alone implements no cutting policy and that no `~JK` is
emitted. The production sequences — `^MMD`, `^MMP,N`, the `~JK` trigger file and
the delayed-cut framing around them — exist only in
`Packages/LabelMac/Sources/LabelMac/FinishingFramedOutput.swift`, whose coverage
is `ProfileBoundFinishingJobPlanTests`. Neither can be compiled or run on Linux,
so neither is bound, and a regression in the production finishing mapping would
not be caught by anything this document certifies. M3-AC03 therefore needs a
hosted macOS run before it can be declared complete, and its checkbox is cleared
rather than left set behind Linux-only evidence.

**M3-AC04 is withdrawn for the same reason.** Ordinary output for a cut, peel or
rewind job is also constructed by `FinishingFramedOutput.swift`, including the
mode command and the delayed-cut trigger files. A persistent or destructive
command introduced into that framing path would leave every artifact this
document certifies green, because no LabelMac test ran here. Its literals are
enumerable and currently contain no reset, calibrate, save, erase or firmware
command, but inspecting literals is not the executed evidence the criterion
needs, and accepting it would apply a weaker standard than the one that
withdrew M3-AC03 one round earlier. Both records need the hosted macOS run
tracked in #103.

**M2-AC05 is withdrawn on the same principle.** The criterion requires preview
reconstruction to match the complete encoder input byte-for-byte. The product
enforces that in `Packages/LabelMac/Sources/LabelMac/WorkerBitmapBinding.swift`,
which re-encodes the accepted bitmap and requires
`encoder.diagnosticFormat(bitmap) == output.zpl` before either render parent will
take worker output. The 132-vector round trip above proves the *engine*
reconstructs its own output exactly; it does not prove the *application* accepts
only that exact encoder input, and `WorkerBitmapBindingTests` did not run here.
The oracle evidence stays in this document because it remains correct and
necessary for that record — it is simply not sufficient on its own.

**M2-AC01 and M2-AC06 were withdrawn on the same principle**, in the round that
also disposed of a claim made earlier in this document. `QuartzPDFRenderer`
holds the Core Graphics extraction that intersects crop and media boxes and
reads `/UserUnit` and `rotationAngle` before a `PDFPageBox` exists; the portable
tests construct `PDFPageBox` directly, so M2-AC01's box/origin/rotation/unit
vectors are not established for real PDF input. For schema-8 finishing jobs the
profile-bound `validateRaster` call is in `FinishingRasterPreparation` and the
bitmap is then written with a generic `ZPLGraphicEncoder`, bypassing
`ZPLPreparedLabelEncoder` entirely, so M2-AC06's profile-limit half has a path
nothing here reaches. Both are in #103.

**M2-AC04 was withdrawn for a portable reason.** `MonochromeConversion`'s
`photographicOrderedDither4x4` branch packs rows itself instead of delegating to
`MonochromeBitmap.threshold`, and is exercised only at widths 2 and 4 while the
criterion names 1, 7, 8, 9, 811, 812 and 813. `MonochromeBitmap.init` validates
tail padding for both packers, so that much is safe, but MSB-first placement at
those widths is not established for the dither path. Closing it needs new test
vectors, which is a LabelCore source change and so a separate PR: #104.

An earlier revision of this document claimed M2-AC04 had no second site. That
audit was wrong — it checked `QuartzPDFToMonochrome`, which does delegate, and
stopped there.

**M3-AC01 and M3-AC02 were withdrawn last, and they are the closest calls.**
`FinishingFramedOutput.prepare` invokes `qualification.validate` immediately
before selecting and emitting `^MMD`, `^MMP` or `^MMR`, and
`FinishingRasterPreparation.validateControls` re-resolves the explicit finishing
choices against the retained profile and rejects a mismatch. Both are *callers*
of LabelCore policy that this run does exercise, rather than independent
reimplementations of it. The argument for keeping the records was that a caller
is wiring rather than an implementation of the claim. It was rejected because
both criteria are stated in terms of what the product does — controls "are not
enabled silently", every explicit choice "is range/combination checked" — and
both enforcement points sit in code nothing executed here reaches. Dropping
either call leaves every LabelCore test in this run green.

The practical consequence, which is the reason this document ends with one
record rather than nine: on Linux, only criteria whose every owner is portable
can be closed. Anything asserting what the product emits, accepts or refuses has
an enforcement site in LabelMac. M2-AC13 survives because it is a statement about
arithmetic rather than behaviour.

This is Linux, Swift 6.1.2, evidence level A only. It qualifies the portable
`LabelCore` engine and the Python oracles. It does not qualify Core Graphics
rendering, `LabelMac`, macOS printing, the scheduler, signing, USB, the GUI, or
any behaviour of a physical GC420d; those remain NOT RUN for lack of a Mac and a
printer in this environment. `label-core-lab` writes diagnostic ZPL to files and
is not a qualified job path; no output here was sent to a device.

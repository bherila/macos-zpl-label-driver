# Current implementation handoff — revision 3

Use the implementation accelerator in [ACCELERATOR.md](ACCELERATOR.md), then the
existing milestone sequence. This revision extends revision 2 without changing
the confirmed GC420d/USB/4x6/tear-off, Tahoe 26, MIT or local-signing baseline.

M0.1 bootstrap is recorded at
`d4dad6d32c0da501e48df45404a8e19b3377d5a9`: the public
`bherila/macos-zpl-label-driver` repository was created with `main` at that
commit after a staged disclosure scan. The repository name replaces the former
generic target throughout the handoff.

On 2026-09-15, the local Tahoe ARM host passed accelerator debug/release
validation (including 34 Python tests, 47 LabelCore tests, 132 independent
ZPL/PBM/analytic round-trips, and 15 inert CUPS ABI cases). LabelMac's Core
Graphics smoke passed in debug and release; the arm64 diagnostic built with a
26.0 deployment target, was ad-hoc signed, verified, and run inertly. These
facts advance M0 automated/native-signing evidence only; they do not establish
installed scheduler, option propagation, document fidelity, hardware, or
release acceptance.

Next safe slice is M1.1/M1.2 proof planning and execution only after explicit
authorization for a finite, clearly named experimental capture queue and its
installation scope. No printer output, queue modification, privileged helper,
or production adapter is authorized by the current evidence.

Reusable components now exist: canonical monochrome packing/threshold/PBM, bounded
uncompressed graphic fields, copy ordering, an offline vector CLI, an inert CUPS
ABI probe, three candidate PPDs and original synthetic PDF/HTML fixtures. Do not
rewrite these as empty skeletons. Run the offline suite before and after changes.

The portable suite is tested on Linux in debug/release; Apple-specific targets
and all actual printing remain untested here. See [ACCELERATOR-VALIDATION.md](ACCELERATOR-VALIDATION.md).
The production PDF renderer, state-control layer, device coordinator/transport,
extraction engine/editor, installer and qualified printer profile are not implemented.

Installation, queue changes, hardware operations, merge and publication still need
the existing authorizations. The probe supports **only** a clearly named discard
queue; successful observation must never be called a printed label. Next high-value
experiment is native Tahoe scheduler admission/options and complete source capture.

M2.1 physical geometry begins at
`e7df7ecf63f7eb71129f760802c2eca229613310`. `LabelCore` now has typed
millimetres, independent horizontal/vertical dots-per-millimetre resolution,
the documented positive half-away-from-zero dot rounding policy, and bounded
dot-canvas planning. The 4×6 GC420d planning oracle is regression-tested as
813×1219 dots, 102 bytes per row, and 124338 packed bytes. This does not yet
perform PDF box/rotation/UserUnit transformation, Quartz rendering, document
capture, queue installation, or printer delivery.

M2.1 PDF page planning extends that portable contract at
`0a4ec84c4e6a1c99cc8a4db8b62db5b361b6a60a`. `NormalizedRect` is constrained
to the upright top-left effective page box and maps once to a clipped original
PDF-box rectangle for each supported rotation. `/UserUnit` affects only
effective physical-size conversion. This is a tested planning contract; Quartz
rendering and real-PDF integration remain M2.2 work.

M2.2 begins at `dd0667288c14377e467c7f226ffdfc4085c14244`. The unprivileged
Quartz renderer accepts bounded original PDF bytes, draws one selected page to
top-to-bottom grayscale with a white background and uniform fit, and rejects
malformed, encrypted, out-of-range, annotation-bearing, or over-limit input.
Native debug and release tests verify a generated source PDF and the output-row
orientation. The renderer does not yet provide packed monochrome output, full
annotation flattening, a cancelable worker boundary, CUPS integration, or any
printer delivery.

M2.3 exact preview begins at `d8a9cbccc7dce8688945eda5df55f404a337be44`.
`MonochromeBitmap` now expands its own canonical packed, top-to-bottom,
MSB-first bytes into a display-oriented grayscale preview while excluding
non-image tail padding. A regression uses a non-byte-aligned, multi-row bitmap
to prove the exact black/white mapping. This advances the preview primitive
only; it does not yet bind Quartz output to thresholding, provide a documented
dither policy, encode a complete production format, or deliver a job.

M2.3 now binds bounded Quartz output to that canonical bitmap at
`87ade157098e340483c96dadbaf8eee017dec5bc`. `QuartzPDFToMonochrome` consumes
the original-PDF renderer's top-to-bottom grayscale `Data` with its exact
stride and applies the deterministic threshold directly into the encoder-input
bitmap; no thumbnail, preview, resampling, or I/O participates. Portable
stride/threshold tests and a native generated-PDF end-to-end test cover the
non-byte-aligned final row and preview equivalence. Dithering, mixed-content
policy, broader PDF-semantic fixtures, complete ZPL preparation, cancellation,
queue integration, and printer delivery remain unimplemented or unvalidated.

M2.3 conversion policy begins at `a62bb9914b79512d25c6b52ed6fa74d1e876da09`.
`MonochromeConversion` makes the choice explicit: text/barcode content uses a
documented strict cutoff, while photographic content uses a fixed, top-left
anchored 4×4 ordered screen. Both consume validated top-to-bottom grayscale
data and produce the same bounded canonical bitmap. Regression cases cover the
cutoff boundary, dither phase, pure black/white endpoints, source-stride
validation, and non-byte-aligned output. A typed job-ticket schema that binds
this policy to user configuration, mixed-region segmentation, physical output,
and scanner validation remain future work.

After each slice, record the actual commit SHA, acceptance IDs advanced, tests run,
results, remaining evidence gates and next safe action. Do not fabricate a repository
commit hash for this preparation archive or convert partial tests into full acceptance.

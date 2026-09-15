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

M2.2 fixture evidence extends at `4c5951bed6f7d5484901e7119c98bf1b2f390140`.
The native test now consumes the supplied, integrity-checked `user-unit` PDF
rather than a regenerated equivalent. Its two physically equivalent pages
produce the identical thresholded packed bitmap—the actual encoder input—even
though Quartz's antialiased grayscale edge samples are not a stable raw-raster
golden. This is a focused original-source/UserUnit regression, not a complete
claim for all PDF semantics, crop extraction, annotation appearance, or physical
label fidelity.

M2.2 crop-box-origin coverage extends at `a05ece360ab1a780b1ab74f37e9c03b7f889c12d`.
The same native packed-bitmap oracle now consumes the supplied `box-origins`
fixture. Its shifted-positive and shifted-negative effective crop boxes yield
identical final packed dots, proving that the Quartz path does not treat a
nonzero page origin as printable content displacement. This remains a focused
full-page fixture check; selected-region clipping and physical placement still
need their separate contracts and evidence.

M2.2 source-document bounds extend at `8134fecb5ae36495cb7427cb81a6c19103e2766e`.
`QuartzPDFRenderer.Request` now bounds source-page traversal independently of
input bytes and output pixels, defaulting to the documented 1,000-page project
limit. Documents over that cap and invalid zero/negative limits fail before page
lookup, rendering, or bitmap allocation; native debug and release regressions
exercise the error. This does not yet provide the separate 60-second isolated
render-worker deadline or cancellation boundary.

M2.6 offline conversion begins at `a07a42b888655a02f757b06898caeaf2cdc5228f`.
The new `label-driver` executable accepts only an explicit, version-1 offline
ticket (page, physical size, dots/mm and monochrome policy), renders the
original PDF, derives the canonical packed bitmap, writes its exact PBM preview,
and emits a bounded uncompressed graphics envelope. Output paths are command
line arguments rather than ticket data; `convert` refuses overwrites, while
`validate` writes nothing. A live synthetic 4×6 conversion produced 813×1219
dots and the independent decoder reconstructed its PBM payload in the expected
321/321/321/256 bands. The JSON result explicitly records no printer I/O and
that the envelope lacks production state normalization. This is not a CUPS
filter, device transport, profile schema, or printer-ready workflow.

At `3ae8d4912f53ad2940f1995c864743e9a4b2d28d`, `convert` also preflights both
the ZPL and preview destinations before it creates either artifact. A known
preview-name collision now exits 73 with no stdout payload and leaves the ZPL
path absent; a post-preflight filesystem race remains reported honestly rather
than being represented as a complete conversion.

At `a017234e1ba2ae99a18879c5ae74e60bd9c8c0cf`, a native executable-level
regression invokes the real `label-driver` binary. It proves `validate` creates
no artifacts, `convert` creates exactly the requested ZPL/PBM pair, and a
repeat conversion exits 73 with no stdout payload. The test uses only a
temporary directory and a synthetic PDF/ticket; it does not enumerate or
contact a printer.

After each slice, record the actual commit SHA, acceptance IDs advanced, tests run,
results, remaining evidence gates and next safe action. Do not fabricate a repository
commit hash for this preparation archive or convert partial tests into full acceptance.

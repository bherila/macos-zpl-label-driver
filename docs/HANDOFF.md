# Current implementation handoff — revision 3


PR #58 second-pass finding 4025638071 exposed review resurrection after an
unsaved edit/undo. The current correction clears acknowledgements on every
successful draft mutation/reload and binds displayed review to a checked edit
generation, rejecting old callbacks even when profile/bitmap values match again.
40 focused native tests passed, including the real-worker undo regression.
At `501cdf1`, full local validation passed exit 0 with 67/173/213 debug/release,
accelerator/independent/inert/signature and packaged-worker equality checks.
Corrected hosted CI is pending. Hosted 35091595114 passed the preceding
`a1e1f58`, not this correction. No third review request or merge is authorized.
The dependent profile-transfer slice remains held until this fix is integrated.

PR #58 first review found restored full-page regions could be approved without
explicit bounds/preview review. Same-branch correction requires acknowledgement
of every region's current packed preview, bound to the complete current profile;
editing/reopening makes prior acknowledgement stale. The button binds its displayed
profile and packed preview, rejecting stale clicks. 39 focused native tests passed.
Initial `5fb351e` full local 67/173/211 debug/release gate passed exit 0 with all
independent/inert/signature/packaged checks; final `a51780f` gate passed exit 0
with 67/173/212 debug/release and all independent/inert/signature/packaged checks.
Corrected hosted/second review pending. See
`validation/M4-EXPLICIT-PAGE-REVIEW-2026-09-16.md`. Original hosted run 35089709098
passed exact `39b2936`; it does not validate the correction. Parent #57 latest
35089708869 passed exact `626122d`; its source first review was clean at `5d9c2c2`.

Latest local slice connects capped canonical workflow JSON import/export through
native dialog adapters. Imports get a fresh unqualified identity; exports verify
the exact own-store saved snapshot. Publication uncertainty retains/reconciles
the same candidate, not a duplicate import. Nineteen focused native tests passed,
including real-worker preservation of the current editor/preview/local approval.
Full gate pending. See `validation/M4-PROFILE-TRANSFER-2026-09-16.md`. No queue,
privilege or device I/O. Noninteractive administrator authorization remains absent.

Latest local slice connects explicit non-label page confirmation and full-page
restoration to the editor's existing typed planner. Page geometry/anchors remain
validated; stale confirmation and last-output-page actions fail without mutation.
Skipped pages remain listed with reasons, and restoration appends a new region
requiring bounds/preview review. Eight portable draft and twelve native editor
tests passed, including real-worker restored preview and immutable saved history.
At `207bdb6`, full local gate passed exit 0 with 67/173/210 debug/release,
independent/inert/signature and packaged-worker equality checks. Own hosted/review
pending. Parent PR #57 hosted 35088846529 passed `5d9c2c2` and first review is clean;
subsequent `626122d` changes evidence only. See
`validation/M4-EXPLICIT-PAGE-HANDLING-2026-09-16.md`.

Latest local slice separates offline editor availability from physical readiness.
Hardware confirmations remain false; installation independently requires both
stock/tear-off confirmations plus discovered identity. Five focused setup tests
passed, including a synthetic identity's four confirmation combinations. Full
pre-merge gate passed at `753fa5a` (67/171/205 debug/release plus independent,
inert, signature and packaged-worker checks); combined `079163a` gate passed
exit 0 with 67/171/209 debug/release and all independent/inert/signature/packaged
checks. Own hosted/review pending. See
`validation/M5-OFFLINE-EDITOR-READINESS-2026-09-16.md`.
Important correction: the earlier nonempty AXWindows result had AXApplication
role and exposed menus, not a verified AXWindow. Both direct and new-instance
Launch Services probes failed the stronger window check. No GUI pass is claimed;
the exact test app namespace has no live instances. Parent PR #56 hosted run
35085759520 passed exact `ef26682`; corrected run 35088390875 remains live,
and second review is clean at unchanged base/head. PR #57 hosted/first review live.
New combined-build Launch Services probes observed one owned layer-zero
WindowServer window each, but AXWindow/control access remains unavailable.
This is stronger evidence of window creation, not GUI/VoiceOver acceptance;
both finite probes closed only owned instances, with no matching live processes
in subsequent exact-artifact inventories. See the same readiness evidence.

PR #56 first review found historical-revision collision, equal-dimension foreign
stock acceptance and unavailable detectors mislabeled as layout changes. Local
same-branch fixes use trusted latest-observed revision allocation for opening,
reload and saved edits; validate stock identity plus dimensions; reject non-border
detectors before worker admission. 52 focused native tests passed; at `4d430c3`,
the complete fail-fast local gate log confirms 67/171/208 debug/release,
independent/inert/signature and packaged-worker checks. Corrected hosted CI and
second review were pending at that initial checkpoint. See
`validation/M4-SAVED-REOPENING-REVIEW-2026-09-16.md`.
Corrected hosted run 35088390875 subsequently passed exact `e00a630`, with
208 native tests debug/release, signatures and packaged-worker equality verified;
second review is clean. No installation or physical result follows from that.
Original hosted run 35085759520 passed exact `ef26682`; it does not validate these fixes.

Latest local slice separates offline editor availability from physical readiness.
Hardware confirmations remain false; installation independently requires both
stock/tear-off confirmations plus discovered identity. Five focused setup tests
passed, including a synthetic identity's four confirmation combinations. Full
gate pending. See `validation/M5-OFFLINE-EDITOR-READINESS-2026-09-16.md`.
Important correction: the earlier nonempty AXWindows result had AXApplication
role and exposed menus, not a verified AXWindow. Both direct and new-instance
Launch Services probes failed the stronger window check. No GUI pass is claimed;
the exact test app namespace has no live instances. Parent PR #56 hosted run
35085759520 passed exact `ef26682`; independent review remains live.

Latest local slice connects saved-revision listing and Reopen with PDF in setup.
It validates the selected immutable snapshot and all original source pages/layout
through the real worker/planner before creating an unsaved correction revision.
Old qualification is retained, never inherited. The bounded descriptor-relative
catalog ignores unpublished staging and rejects unsafe/malformed candidates.
48 focused native tests passed. Initial `3118dbb` passes full local 67/171/203
debug/release, independent/inert/signature/packaged-worker checks. Final
`b836b42` passed full local 67/171/204 debug/release plus all independent/inert,
signature and packaged-worker checks. Own hosted/review pending. See
`validation/M4-SAVED-WORKFLOW-REOPENING-2026-09-16.md` for limits and finite unrun
GUI procedure. Parent PR #55 run 35084288575 passed exact `55dd7d2`, and its first
independent review is clean. No scheduler, installation or physical result added.
Native AX trust is available. A finite direct-executable GUI probe observed our
an AXApplication/menu element, not a verified AXWindow; expected-control lookup failed. All owned instances were
closed/reaped, with no button actions or hardware assertions. GUI acceptance is
unproven. Next: separate offline editing from actual stock/tear-off confirmation
and resolve the bounded accessibility traversal rather than fake hardware facts.

Current local slice connects add/remove region controls to the typed draft, with
global order, original-source child previews and immutable revisions preserved.
The last region on a page cannot be removed implicitly. At `fafd7a1`, six portable
draft and eleven native editor focused tests plus full local 67/171/194
debug/release, independent/inert/signature/packaged-worker checks passed. Own
hosted CI/review pending. See
`validation/M4-MULTIPLE-REGION-EDITOR-2026-09-16.md`. Parent PR #54's hosted run
35083659869 passed exact `2bf83ba`, and its first independent review is clean.

Latest local slice: source-page dragging now commits normalized extraction
bounds through the existing editor model, with captured region/viewport guards.
Saved-workflow edits advance an immutable revision without overwriting the old
record. Implementation `3c5b7d6` passed two portable selection and ten native
editor focused tests plus the full local 67/169/193 debug/release gate,
independent/inert/signature and packaged-worker checks. Own hosted/review pending.
See `validation/M4-DRAWN-REGION-SELECTION-2026-09-16.md` for limitations
and the finite, unrun GUI procedure. Parent PR #53 at `64a22f3` has passing
hosted run 35082704430 and a clean independent review. No queues or hardware used.

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

The finite M1 discard-queue experiment is authorized, but it has not run because
noninteractive administrator authorization is unavailable on the observed host.
No queue, protected path, global scheduler setting, or printer was changed.

M1 preflight on Tahoe ARM is recorded in
[M1-TAHOE-CAPTURE-2026-09-15.md](validation/M1-TAHOE-CAPTURE-2026-09-15.md).
The candidate PPDs now pass native `cupstestppd -v` with standard full-bleed
media names, and the inert probe's release build/signature were verified. The
only attempted installation action was a non-interactive authorization check,
which was denied; no backend, queue, printer operation, or global CUPS change
occurred. M1 installed-scheduler evidence remains blocked until the local
supported administrator authorization path is completed.

Reusable components now exist: canonical monochrome packing/threshold/PBM, bounded
uncompressed graphic fields, copy ordering, an offline vector CLI, an inert CUPS
ABI probe, three candidate PPDs and original synthetic PDF/HTML fixtures. Do not
rewrite these as empty skeletons. Run the offline suite before and after changes.

The portable suite is tested on Linux in debug/release; Apple-specific targets
and all actual printing remain untested here. See [ACCELERATOR-VALIDATION.md](ACCELERATOR-VALIDATION.md).
The Quartz PDF renderer, typed GC420d baseline controls, delivery-state model,
raw-TCP simulator path, cross-process lease primitive, and offline conversion CLI
are implemented with the partial evidence recorded below. The accepted production
CUPS adapter, USB delivery, extraction engine/editor, installer, and physically
qualified printer profile are not implemented or accepted.

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

At `d6e6a8627805605fc15e806bac5dc782543705fa`, `--json` errors gained stable
stderr records with `USAGE`, `INPUT_ERROR`, or `OUTPUT_ERROR` codes while
retaining conventional nonzero exits. The executable regression confirms that
a malformed ticket returns exit 65, writes nothing to stdout, and yields an
`INPUT_ERROR` JSON object on stderr. This establishes only the offline CLI
contract; a CUPS filter's stdout/stderr contract remains unproven.

M3.1 begins at `9a6e0fb391f3b54f994d453cd53edbba2667a4dc`. `LabelCore` now
has a versioned, typed GC420d USB reference profile with provenance-bearing
tri-state facts. Documented model facts remain distinct from installed-unit
observations: thermal transfer is unsupported, model cutter/peeler/rewind
facts remain unknown where the documentation does not establish them, while
the reported installed cutter is absent and the selected tear-off setup is
explicit. Current speed, darkness and tracking remain `nil`; no missing value
becomes a guessed default. Portable regression vectors permit only documented
2/3/4 ips and direct thermal/tear-off, reject transfer/cut/peel/rewind/speed
5, and reject explicit darkness or tracking until their installed values and
mapping are qualified. This partially advances M3-AC01, M3-AC02 and M3-AC13
at automated evidence only. It emits no ZPL controls, device query, persistent
command, queue change, or transport I/O; M3-AC03 through M3-AC12 remain open.

The next safe M3 slice is deterministic settings resolution and a
protocol-provenance table, retaining `leave unchanged` for unobserved values.
It must not promote the offline diagnostic graphics envelope to production
control output or contact the USB device.

At `0ed6031e90975a494945bcad73c44dc67c29d2c3`, control resolution now has one
typed precedence rule: explicit job choice, then immutable workflow defaults,
then the configured installed-device value. The resulting record includes the
profile schema/revision and uses an explicit `leaveUnchanged` case rather than
inventing a current speed, darkness, or tracking value. The reference profile
therefore resolves direct thermal and selected tear-off, while its unobserved
speed/darkness/tracking settings remain unchanged. Regression tests prove
revision binding, precedence, and rejection of an unsupported workflow speed.
This advances only the portable portion of M3-AC02/M3-AC13; it creates no ZPL,
transport traffic, persistent configuration, or device I/O. The next slice is
a cited control-protocol table and bounded encoder, with ordinary-job output
forbidden from reset, calibration, save, erase, or firmware commands.

At `37d1a0e88bba2bac5e014b519c685b95db00fc80`, the core has a bounded,
typed session-control encoder with a compact protocol table. For the reference
profile, it emits only `^MMT` for the selected tear-off mode and `^PR` for a
validated 2/3/4 ips choice; both entries point to their documented sources.
Darkness, tracking, dimensions, offsets, copies and all unqualified accessory
controls remain unencodable. Regression vectors prove the exact small output,
the output cap, source identifiers, and absence of reset/calibrate/save/erase,
firmware, image-threshold, media-size, copy, or storage commands. This is
portable partial M3-AC03/M3-AC04/M3-AC13 evidence only: it is not a complete
production label envelope and has no queue, USB, network, or physical result.

M3 delivery-state work begins at `5026353212f7d26933904cc6d93ec711a0339601`.
The portable tracker distinguishes accepted, prepared, waiting, transmitting,
transmitted, device-confirmed, uncertain, failed-before-transmission, and
cancelled-before-transmission states while binding the profile revision and
expected byte count. A completed local write is not physical confirmation.
Only a failure before any transmission may be automatically retried; partial
write, post-send disconnect, crash, and cancellation ambiguity become
`uncertain` and require explicit review. Regression tests cover these paths and
invalid state/byte transitions. This is portable partial M3-AC09 evidence only;
no scheduler retry behavior, backend, USB, network, or physical test has run.

At `f20620d`, `BoundedDelivery` connects a bounded byte-sink contract to the
delivery tracker. It consumes short writes until all expected bytes are locally
accepted, rejects zero and out-of-range write counts, marks failure before any
accepted byte as retryable, and converts later failures to `uncertain`. Its
in-memory regressions cover 2+2+1 byte delivery, a zero-byte pre-send failure,
and a zero-byte failure after two accepted bytes. This is partial portable
M3-AC05/M3-AC09 evidence only; it is not raw TCP, USB, scheduler, or hardware
validation.

At `cbb62f842b932a41ec3ab046efb076c711476290`, a prepared-label encoder joins
typed baseline controls and the canonical graphics writer in exactly one
bounded `^XA`/`^XZ` envelope. Its regression checks the complete golden
sequence, single-wrapper invariant, total-budget preflight, and the continued
absence of copies, reset/save, darkness, media-size, and storage commands.
This avoids treating the old diagnostic envelope as production output, but is
still only portable prepared-output evidence: no transport, scheduler, USB,
network, or physical printer acceptance has occurred.

At `422a0c72eff6420f57658db2f9d21e401c2f60c9`, the prepared-label encoder
removed forced construction of its default subencoders. Defaults now propagate
configuration errors through the throwing initializer rather than crashing if
future bounds change. The existing 81-core-test suite passes; this is a safety
fix with no device or transport effect.

At `25f33ed79ff8ccb669854f446c647399dba5da74`, M3.3 gains an explicitly
configured `Network.framework` raw-TCP delivery boundary. It validates a
bounded host/port and timeout without scanning or logging endpoints, sends one
prepared byte stream, and records only local transport completion. The
localhost-only regression uses an ephemeral listener to prove the exact payload
arrives and that the result is `transmitted`, never device-confirmed. A timeout
or send failure after invoking the network send operation now maps to the new
zero-count *uncertain attempt* state: zero is unknown rather than a safe retry
signal. Endpoint and timeout rejection vectors also pass. This advances only
portable/macOS simulation portions of M3-AC05 and M3-AC09. It has no printer
discovery, printer connection, USB path, scheduler/backend integration,
cross-process coordination, status protocol, or hardware evidence.

The full local gate passed on Tahoe ARM after this slice: accelerator checks;
repository preflight; 34 Python tests; 82 LabelCore tests; 11 LabelMac tests
(including the loopback TCP vector); and `scripts/ci-swift.sh` (132
cross-language ZPL/PBM/analytic round-trips, with its documented inert output).
The expected malformed-PDF Core Graphics diagnostic was observed in its
negative test. The next safe M3 work is a bounded simulated-fault harness for
the remaining raw-TCP failure modes, followed by the separate cross-process
ownership boundary; neither unlocks USB or physical acceptance.

At `f579d3164a8ce84ef422cc681461573b4bb5e816`, M3.5 begins with a
macOS-only `flock` lease keyed by a validated stable physical-device identity.
The on-disk filename is SHA-256-derived rather than the supplied identity;
creation rejects non-regular or linked files, and the lock is tied to an open
descriptor so the kernel releases it on close or process exit rather than a
stale PID-file convention. The inert diagnostics tool has a bounded
`--hold-device-lease` probe with no device, network, queue, or document
operation. Its regression starts a real child process, proves a second holder
is rejected, terminates the child, and proves immediate reacquisition. It also
covers explicit release, alias collision, opaque naming, and unsafe inputs.
This is partial M3-AC07/M3-AC08 automated/macOS primitive evidence only: no
two CUPS queues, maintenance path, transport lifetime, or actual device output
has used the lease, so the integration acceptance items remain unchecked.

The full local gate passed after this slice: accelerator checks; repository
preflight; 34 Python tests; 82 LabelCore tests; 13 LabelMac tests (including
loopback TCP and child-process lease regressions); and `scripts/ci-swift.sh`
(132 inert cross-language ZPL/PBM/analytic round-trips). The expected malformed
PDF Core Graphics diagnostic was observed in its negative test. Next, retain
the lease as an unintegrated primitive until M1 establishes a scheduler backend
contract; continue the raw-TCP loopback fault harness without treating either
path as USB, queue, or physical-printer proof.

At `d4233ede88d548cdd58b8526cc87e32e4e416535`, raw-TCP outcome resolution is
now a deterministic seam shared by the Network.framework adapter and
regressions. The loopback listener still proves a real local stream transfer;
the new fault vectors prove every adapter outcome maps to an honest receipt:
pre-send connection/timeout failures are retryable, while a timeout or send
failure after the send attempt is `uncertain(bytesAccepted: 0)` and cannot
become device-confirmed. This improves partial M3-AC05/M3-AC09 automated
evidence only. Network.framework still owns real stream segmentation and its
callback cannot reveal a peer byte count; no synthetic result is presented as
USB, scheduler, device-status, or physical-print evidence.

At `5a9be59d8e93e8a0b1f8cd3ca3e549e21dcfbed9`, M1.1 gains a separate inert
Swift CUPS filter executable, `labelcapture-filter`, to pair with the existing
discard-only `labelprobe` backend. It accepts the documented positional job ABI,
validates bounded input/options before streaming the exact original bytes to
stdout for the next stage, and emits only sanitized stderr metadata. It has no
destination selection, retained payload, network/device access, recursive
scheduler call, or installation behavior. Its user-space vectors prove file and
stdin preservation plus safe rejection of unknown options, symlinks, oversized
regular files and empty input; the existing probe remains the only allowed
`labelprobe://discard` backend. This is portable implementation evidence toward
M1-AC09 only, not scheduler execution, page-fidelity, dialog-option, sandbox,
installation, transport, or local-signing acceptance. The M1 experimental queue
remains uninstalled pending the separately recorded administrator-authenticated
Tahoe procedure.

At `ad069255898e4a0e97684fc534cd82dd90aedfb9`, the offline accelerator suite
adds a finite filter-to-discard-backend pipeline vector. It connects the real
`labelcapture-filter` stdout to the real `labelprobe` stdin, then proves exact
byte counts and all four typed experimental controls survive the pipeline while
the synthetic private marker remains absent from both diagnostics. The backend
still reports no physical output and the filter retains no payload. This is
additional portable M1.1 plumbing/privacy evidence only; neither process was
run by CUPS, installed, or connected to a printer.

The sanitized host preflight at `docs/validation/M1-TAHOE-HOST-PREFLIGHT-2026-09-15.md`
records Tahoe 26.6.2/ARM, a running local scheduler, and a pre-existing physical
configuration without retaining its identifiers. CUPS reports a root-owned
server executable area and no supported writable add-on placement was established
from the read-only inspection. No artifact/queue/default/printer changed. This
is a real M1 architecture blocker, not permission to copy binaries into a
system directory or to weaken the authorization boundary; all M1 acceptance
items remain unchecked.

At `aa909f6`, the host-preflight blocker now cites the public CUPS `ServerBin`
contract: filters/backends reside under the scheduler-configured binary directory
and changing that setting requires a scheduler restart. That supports the existing
decision not to redirect CUPS globally merely to install this experiment; it is
not evidence of a supported Tahoe add-on path or scheduler admission.

At `d0581646b4567b829a8e5f8ed28cc70652e7b4e9`, the inert capture filter gained
a small C bridge to CUPS `cupsParseOptions`/`cupsGetOption`. It parses the real
CUPS option wire string and cross-checks the result against the existing strict
experiment choices, retaining duplicate/invalid-value rejection rather than
silently taking a parser-selected value. This advances source-level M1 option
handling only; it is not the product ticket schema, installed filter evidence,
or proof that Tahoe's dialog exposes or propagates a given option.

At `8c22965`, `PrinterProfile` construction now rejects blank/control-character
model identifiers, nonpositive documented speed choices, and nonpositive
observed current speeds before a profile can bind a job. Regression vectors
cover each rejection. This is additional portable M3-AC01/M3-AC02 evidence
only: it does not infer a darkness range, tracking mode, media dimensions,
offset, current device setting, protocol command, scheduler result, or physical
printer behavior. The immediately preceding hosted macOS 26 ARM run for
`34a3d88` completed successfully; it validates that earlier CUPS option-parser
slice, not this new commit. Next safe action is to run the full local Mac gate
for this profile slice and then queue its own hosted CI run; USB, CUPS
installation, and physical-device acceptance remain blocked on their separate
evidence.

At `a520fb6`, the real inert-filter ABI regression now passes quoted known
option values through both CUPS parsing and the strict experiment schema.
The test still uses synthetic bytes and the discard-only next stage, and checks
that its private marker is absent from diagnostics. This is a small additional
portable M1 option-wire regression only: it is not scheduler execution,
print-dialog propagation, payload capture, installation, device access, or
physical-printer evidence.

At `722dd5e`, the versioned printer profile now binds a typed media record.
The GC420d reference records only the reported pre-cut nominal 4×6-inch face;
configured tracking and calibrated printable width/length/origin remain
explicitly unobserved. A calibration object rejects nonpositive dimensions,
and the regression proves the nominal face cannot be treated as calibration.
This is portable partial M3-AC01/M3-AC02/M3-AC13 evidence only. It does not
emit `^LL`, `^PW`, `^LS`, or any position command; no imageable area, gap,
tracking setting, current printer state, scheduler result, or physical output
has been inferred or observed. Next safe M3 work is to connect this immutable
media snapshot to prepared-job state without enabling unqualified controls.

At `a390ab4`, `DeliveryTracker` gained a typed-profile initializer that copies
the profile schema version, revision, and media record into its receipt at
acceptance. The regression proves a later profile revision cannot rewrite that
receipt; revision-only transport callers remain explicitly snapshot-less rather
than fabricated. This is portable partial M1-AC07/M3-AC01/M3-AC09 evidence
only. It does not yet bind a real scheduler job, persist/recover a held job,
choose a transport, emit a media command, install a queue, or establish device
delivery/physical acceptance.

At `fcfc264`, explicit width, length, and origin requests gained a typed
control representation. Nonpositive dimensions fail at construction; valid
requests from either job or workflow defaults fail against the GC420d reference
until a measured calibration and cited ordinary-job mapping exist. This closes
the silent-drop path without turning the 813×1219 planning face into `^LL`,
`^PW`, or offset output. It is portable partial M3-AC02/M3-AC03/M3-AC04/
M3-AC13 evidence only. Darkness/tracking/media command qualification, queue
option propagation, USB delivery, and physical validation remain open.

At `2dac751`, `ZPLPreparedLabelEncoder.prepare` now resolves controls from one
typed profile and returns bounded bytes paired with that exact immutable
profile/media snapshot. `DeliveryTracker(preparedLabel:)` receives the same
snapshot and derives its byte count from those prepared bytes. Regression
proves the single-envelope payload and receipt preserve revision 23 together.
This is portable partial M1-AC07/M3-AC01/M3-AC09 evidence only; it has no
spooler persistence, scheduler hold/release result, process-wide ownership,
USB/network delivery, status receipt, or physical output evidence.

At `e716fe6`, the raw-TCP adapter gained a preferred `PreparedLabel` handoff.
It delivers those exact bytes while preserving the embedded profile/media
snapshot in every result state. The older revision-only API remains explicitly
snapshot-less for compatibility; it cannot fabricate a profile. The loopback
and deterministic-fault seams prove local transmission and conservative failure
states only. This is portable/macOS-simulation partial M1-AC07/M3-AC05/M3-AC09
evidence, not a network-printer, USB, scheduler, status, or physical result.

At `ab97ab3`, the immutable profile gained a typed connection record. The
reference declares USB transport while keeping its stable identity unobserved;
when a future local identity is supplied, it is bounded, opaque, and redacted
by default. Regression verifies invalid inputs and string/debug redaction.
The initial LabelMac test run after this profile-layout change hit a signal-11
in stale cross-package SwiftPM artifacts; cleaning both package build products
and rebuilding reproduced no crash (88 LabelCore and 17 LabelMac tests passed).
This is portable/macOS automated partial M3-AC01/M3-AC12/M3-AC13 evidence
only: it does not enumerate USB, reveal an identifier, establish a coordinator
key, install a backend, send a command, or qualify physical delivery.

At `6f6e190`, profile construction rejects a connection transport that differs
from the installed-hardware transport. The regression proves a raw-TCP
substitution cannot be paired with the GC420d USB reference. This is portable
partial M3-AC01/M3-AC13 evidence only; it does not make USB delivery available
or test any connection identifier, queue, scheduler, or physical device.

ADR 0003 records the current M1 go/no-go boundary: the portable CUPS filter,
discard probe, option parsing, prepared-profile snapshot, and lease tests do
not establish a supported Tahoe placement, scheduler admission, or local
ad-hoc installer authorization path. The production adapter remains
unselected. It explicitly prohibits installing the discard queue, copying into
a scheduler directory, changing scheduler configuration, or starting an IPP
alternative merely to infer native behavior. This advances M1-AC12
configuration/decision evidence only; M1-AC01 through M1-AC11 and M1-AC13
remain unchecked. The next finite action is a reviewed Tahoe placement and
narrow authorization design, followed only then by the reversible discard-queue
experiment.

The inert filter's portable ABI harness now holds an open stdin pipe, sends
`SIGTERM`, and verifies bounded non-success termination without diagnostic
payload leakage. It also supplies a closed stdout reader and verifies that the
filter's ignored `SIGPIPE` becomes a non-successful bounded write failure,
again without reflecting private input. The harness now has eight cases. This
is additional partial M1-AC09 preparation only: it does not establish CUPS
signal delivery, scheduler cleanup, installed queue behavior, or a physical
printer result. The next safe action remains a reviewed Tahoe placement and
narrow authorization design before any discard-queue installation.

The reviewed M1 installation candidate is now
`scripts/m1-discard-file-sink.sh`. It leaves the custom `labelprobe` backend
uninstalled rather than placing it under `ServerBin`. With a separate
interactive administrator approval, its fixed allowlist can stage only the
locally ad-hoc-signed filter below an owned local printer directory, create only
`LabelProbe_DISCARDS_JOBS`, and point that queue at CUPS' existing
`file:///dev/null` sink. It never changes a default, global scheduler setting,
or physical destination. The supplied candidate PPD is generated in a private
temporary directory with only its two PDF filter-program declarations replaced
by the fixed absolute filter path; removal first verifies the exact sink and
then removes only the recorded owned artifacts. Plan mode, PPD materialization,
and fixed-boundary regressions pass. Administrator authentication is currently
unavailable, so no queue, protected file, scheduler, or device was changed.
This is M1 portable/procedure preparation only; actual scheduler admission,
dialog behavior, document fidelity, cancellation, profile snapshots, and
local-signing feasibility all remain unchecked until the finite Tahoe experiment
runs.

The post-staging failure path was corrected before any administrator session was
used: Bash commands guarded by `||` do not invoke the `ERR` trap, so strict PPD
validation or queue-URI readback could otherwise have bypassed automatic
cleanup. Those two paths now call the same fixed-target cleanup routine
explicitly; trap-driven failures use it as well. Regression assertions cover
both calls. This remains source-level transaction safety evidence only, with no
queue or protected artifact created.

The first hosted run for the initial transaction commit failed in the Linux
repository-preflight job because that standard runner has no `cupstestppd`.
The PPD-materialization test now uses that validator when available and still
asserts the exact generated declarations everywhere; Tahoe's transaction itself
continues to require pre-stage and post-stage `cupstestppd` validation. This is
a test-environment correction, not macOS evidence.

The discard-queue transaction now verifies its protected ownership fields and
the staged filter SHA-256 before removing files. Removal may safely resume when
the owned queue is already absent, but refuses a present queue whose URI no
longer matches the fixed inert sink. Apply also reads back that the experiment
did not become the system default and invokes fixed-target cleanup if it did.
These guards close replacement and partial-removal hazards in the candidate
procedure; they remain unexecuted source-level evidence until an administrator
is present for the authorized Tahoe experiment.

The transaction also snapshots the selected user-writable filter into its
private temporary directory before validation, computes the approved SHA-256
from that snapshot, stages only those bytes, and compares the protected copy to
the approved hash before creating a queue. The ownership record receives that
same hash. This closes the earlier verify/copy/hash substitution window without
claiming that an ad-hoc signature authenticates a publisher. The check remains
unexecuted under administrator authorization.

The supplied candidate PPD is now copied into the same private temporary
directory before validation and rendering, so a user-writable source change
cannot alter the generated privileged transaction between those two steps.
The generated PPD remains a narrow transformation of that snapshot and is
strictly revalidated after the fixed filter is staged.

The candidate now rejects a merely valid but wrong signing/platform artifact:
before staging and again afterward it requires `Signature=adhoc`, no certificate
authority, an arm64 Mach-O slice, the macOS platform, and an exact 26.0 minimum
load command. This validates the declared M1 experiment artifact contract; it
does not establish scheduler admission or public trust.

That artifact check is exposed as the read-only `--validate-filter` mode and is
part of `scripts/ci-swift.sh` for the real release `labelcapture-filter`. Its
first local execution caught an incorrect `lipo -verify_arch` argument order;
after correction, the same built artifact passed ad-hoc identity, no-authority,
arm64, macOS-platform, and 26.0-minimum checks. This is actual local artifact
metadata evidence, still not scheduler execution.

At `f6cb7fb`, the privileged experiment was narrowed to the exact SHA-256 byte
sequences of the three supplied candidate PPDs. Validation also requires exactly
the two expected `cupsFilter2` declarations and rejects legacy `cupsFilter`
directives. The ownership record now retains the source PPD hash, has an exact
six-line shape, and removal rejects a missing or symbolic-link filter. Local
validation passed 38 Python tests, 89 LabelCore tests, 132 independent encoder
round trips, 15 backend ABI cases, eight filter ABI cases, and one inert
filter-to-discard pipeline case. This is source-level transaction safety evidence
only; administrator-backed scheduler admission remains not run.

At `b820b18`, a pre-install review caught that Bash would run the EXIT trap only
after the apply function's local temporary-path variable left scope. Under
`set -u`, that could preserve the private filter and PPD snapshots. The path is
now process-scoped, fixed below `/private/tmp`, and guarded before recursive
removal; a real invalid-artifact invocation proves pre-authorization cleanup.
The protected experiment root is also a single owned directory, so removal
cannot strand a parent created by `mkdir -p`. Local validation passed 39 Python
tests, 89 LabelCore tests, 132 independent encoder round trips, 15 backend ABI
cases, eight filter ABI cases, and one inert pipeline case. No administrator
authorization, queue, protected file, scheduler job, or device access occurred.

At `33e5edd`, rollback became ownership-conservative under concurrent or partial
state changes. It removes the named queue only while its URI still equals the
inert sink, removes staged files only after exact root/record/hash checks, and
requires the recorded source PPD hash to remain one of the three supplied
candidates. Missing or altered state is retained with a warning for finite
diagnosis rather than guessed to be owned. The root is created without `-p`, and
staging flags are set before writes so partial operations enter the guarded
cleanup path. The offline accelerator suite remains green with 39 Python and 89
LabelCore tests plus all independent ABI/oracle checks. These are unprivileged
source and regression results only; the privileged branches remain not run.

At `724cb13`, the concrete fixture corpus gained a deterministic interactive
AcroForm document containing one canonical text field, one Widget annotation,
and a nonempty normal appearance stream. Generator and manifest checks reopen
and verify the field value and appearance; a 144-DPI Poppler rendering was
visually inspected with the value visible and unclipped. The Tahoe Core Graphics
test proves `QuartzPDFRenderer` rejects this document as
`annotationsUnsupported` before rasterization rather than silently omitting the
appearance. LabelMac passed 18 tests, the fixture corpus passed at 18 PDFs/28
pages plus three HTML files, and the offline accelerator suite remained green.
The optional whole-corpus barcode recheck was NOT RUN because the local ZBar
shared library is absent; no dependency was installed globally. This is partial
automated M2-AC03/M2-AC09 evidence only, not application, scheduler, physical,
or general PDF-form acceptance.

At `69e7c6e`, Tahoe Core Graphics regressions now inspect actual semantic pixels
from the supplied transparency and embedded-raster fixtures. The transparency
sample must composite to a bounded intermediate gray against the renderer's
explicit white background while the adjacent pixel remains white. Both the
low- and high-resolution embedded raster pages must retain black and white
structure in their declared physical region. All 20 LabelMac tests pass. This
adds partial automated M2-AC03 evidence; it does not establish every PDF blend
mode, low-resolution warning UX, application capture, or physical image quality.

At `11d9c70`, the mixed-size two-page fixture now has a per-page placement oracle.
At the same final dot canvas, the native 4x6 page's full-face border and the
Letter page's inset label border must appear at distinct measured columns. This
would fail if the renderer reused the first page's geometry or treated
application-facing Letter stock as a native label. It is additional partial
automated M2-AC02/M2-AC03 evidence only; M1 must still establish what each real
application supplies to the queue.

At `c7f4a5e`, offline conversion no longer writes printer-language output before
its exact packed-bitmap preview. The CLI rejects identical destinations, writes
the preview first, and removes that owned preview if the subsequent ZPL creation
fails. A real overlong-filename failure injected after destination validation
proves neither file remains; a second regression proves an aliased output pair
writes nothing. All 23 LabelMac tests pass. This is partial automated M2-AC05/
M2-AC09/M2-AC10 evidence for the offline CLI only. It is not a crash-atomic
multi-filesystem transaction, scheduler filter contract, or delivery result.

At `5aec8ee`, each final CLI output is now published by a same-directory staged
file and Darwin `renameatx_np(..., RENAME_EXCL)`. This preserves no-overwrite
behavior while ensuring a final preview or ZPL path never exposes a partially
written file. Preview still commits before ZPL, so a crash between final renames
can leave a complete preview but not a final ZPL without its preview; ordinary
second-write failure removes the preview and leaves no staging artifacts. The
first attempt to combine Foundation `.atomic` and `.withoutOverwriting` aborted
with an explicit unsupported-options failure and was replaced before commit.
All 23 LabelMac tests pass. This strengthens partial M2-AC09/M2-AC10 evidence;
the two-path pair is intentionally not claimed as one cross-filesystem atomic
transaction.

At `3fcca54`, the CLI validates regular-file type and byte size before mapping
either the PDF or job ticket, then rechecks the mapped byte count to close a
change-during-read over-limit path. Offline conversion now names its 100 MiB PDF
cap and passes it explicitly into the Quartz request; job tickets have a separate
64 KiB cap. Sparse 100 MiB-plus-one PDF and 64 KiB-plus-one ticket regressions
both fail with input exit 65 before preparation or output. All 24 LabelMac tests
pass. This is partial automated M2-AC09/M2-AC10 evidence; it is not the required
cancelable worker deadline or protection against every hostile filesystem.

At `7963306`, the real offline CLI now delegates PDF parsing, Quartz rendering,
monochrome conversion, and diagnostic ZPL preparation to a separate unprivileged
`label-render-worker`. The parent creates a mode-0700 private scratch directory,
passes only that directory with fixed protocol filenames, bounds and reads regular
artifacts without following symbolic links, and removes scratch on every normal,
failure, timeout, and cancellation return. A 60-second page deadline terminates
only the owned worker, with SIGKILL escalation after a bounded grace period; CLI
SIGINT/SIGTERM feeds the same cancellation path. Worker result, preview, and ZPL
sizes are independently capped and validated before the existing exclusive final
publication path can run. Native debug and release suites passed 28 tests,
including real worker success, malformed-input failure, forced timeout, explicit
cancellation, and executable-level conversion. The complete offline accelerator
suite also passed (39 Python tests, 89 LabelCore tests, 132 independent round trips,
15 backend ABI cases, eight filter ABI cases, and one inert pipeline case). All
three command-line products built arm64 with minimum macOS 26.0 and passed local
ad-hoc signature verification; only the inert diagnostic was executed by that
signing smoke. This is substantive automated M2-AC09/M2-AC10 evidence, but installed
CUPS cancellation/stdout behavior, hostile worker compromise containment, physical
output, and clean-host admission remain unverified, so neither item is checked.

At `28e24fe`, worker failures gained a separate bounded, versioned, allowlisted
failure record. The subprocess never serializes framework descriptions, paths, or
document content; the parent trusts the record only after a normal nonzero exit and
otherwise reports a generic worker failure. The CLI now preserves stable categories
for invalid tickets, malformed/unsupported input, encryption, unsupported annotations,
page selection, limits, geometry, and rendering/preparation failure. Real subprocess
tests prove malformed PDF and invalid-ticket categories, and unit classification keeps
encrypted input distinct from malformed input. Native debug and release suites pass
30 tests. At that commit an encrypted PDF fixture was still absent, so encryption
had classification coverage only; `fb66dad` below closes that fixture gap. This
advances partial M2-AC09/M2-AC10 evidence without closing either acceptance item.

At `fb66dad`, the synthetic corpus gained a reproducible password-protected PDF,
derived from the existing native vector label and indexed with public test-only
credentials. The development-only generator uses qpdf static-ID, non-AES 128-bit
encryption solely to keep fixture bytes deterministic; this is explicitly not a
runtime dependency or cryptographic recommendation. Two consecutive regenerations
produced SHA-256 `94d4b9018a89f8972dadeaeade0add2bb3844a3757bb218a82657c622c504031`,
and qpdf found no syntax or stream errors with the fixture password. Quartz rejects
the concrete file as encrypted. The real worker preserves that category, while a
truncated derivative of the concrete native fixture is rejected as unsupported.
An executable CLI regression proves encrypted `convert` exits 65 with
`INPUT_ENCRYPTED`, empty stdout, and no final ZPL or PBM. The first expanded-suite
run correctly failed its stale 18-PDF/28-page count oracle; after updating that
explicit expectation to 19/29, all 39 Python checks, 89 LabelCore tests, 132
independent round trips, ABI/pipeline checks, and 33 release LabelMac tests passed.
This adds concrete partial M2-AC09/M2-AC10 evidence; supported password entry or
decryption is not implemented or claimed.

At `bc63ae8`, the CLI source/ticket reader and parent-side worker-artifact reader
were unified behind a descriptor-based bounded regular-file primitive. It opens the
final component with `O_NOFOLLOW`, verifies type and declared size on the same file
descriptor, reads at most the configured cap plus one sentinel byte, and rejects
identity, size, modification-time, or change-time drift before returning bytes.
Private worker artifacts additionally require current-user ownership and exactly one
hard link. Regressions cover exact-limit reads, over-limit rejection, invalid caps,
symbolic links, directories, hard-linked private artifacts, and a real CLI symlinked
PDF rejection. Native debug and release suites pass 36 tests; the focused final
reader rerun passes three tests. This adds partial automated M2-AC09/M2-AC10
filesystem-safety evidence, not a claim that every hostile filesystem or installed
CUPS spool-file behavior has been qualified.

At `46a6ec0`, cancellation is exercised through the real CLI signal boundary rather
than only by calling the worker coordinator. The regression launches an under-limit
8,192×4,000-dot photographic conversion, waits until the CLI has created its private
worker scratch, sends SIGTERM to the CLI, and requires a normal exit 130 with the
stable `CANCELLED` error. It also proves stdout is empty, neither final ZPL nor PBM
exists, and the newly observed scratch directory is removed. The test passes alone
and in the complete 37-test LabelMac debug and release suites. This strengthens
automated M2-AC09/M2-AC10 evidence for the offline executable; installed scheduler
signal delivery and filter exit interpretation still require M1 integration evidence.

At `b404f0c`, PDF placement became an explicit physical contract instead of an
implicit pixel fit. `PagePlacementPlanner` provides centered `fit` and
`actualSize` policies, converts through independent horizontal and vertical dot
pitch, bounds target dimensions, and reports the visible clipped rectangle. The
Quartz renderer derives each selected page's effective crop-box size from its
origin, rotation, and `/UserUnit`, then renders once into the planned dot rect;
the version-1 offline ticket carries the policy and continues to default to fit
when the field is absent. Portable regressions prove non-square-pitch fitting,
actual-size clipping, and that changing only `/UserUnit` changes physical extent.
Native regressions prove compensated geometry remains identical, square content
is not distorted on a non-square-pitch canvas, and existing transparency,
raster, origin, and mixed-page semantics remain intact. Debug/release suites pass
93 LabelCore and 39 LabelMac tests, and the full offline accelerator passes. This
adds partial automated M2-AC02/M2-AC03 evidence only; extraction placement,
installed application capture, scheduler fidelity, and physical output remain
unverified.

At `c2f0c1a`, the M1 candidate assets and capture-filter output path were
reconciled with review findings R6/R7. All three PPDs now use consistent
full-bleed media keys; their new exact SHA-256 values are pinned by the
transaction, and a read-only validation mode accepts every supplied candidate
while rejecting a one-byte mutation before authorization. The filter recognizes
its configured `application/vnd.labelprobe` final MIME and makes stdout
nonblocking before delivery. Its poll loop continues through temporary
backpressure until the actual deadline, handles short writes, and never enters a
deadline-free blocking write. Process regressions fill the output pipe, prove a
consumer delayed beyond one poll interval succeeds, prove a permanently stalled
consumer fails at the ten-second bound, and retain the closed-consumer failure
case. The offline accelerator passes with 42 Python checks, 93 LabelCore tests,
132 independent round trips, 15 backend ABI cases, ten filter ABI cases, and one
inert pipeline case. This closes the identified source-level R6/R7 defects; it
does not establish scheduler admission, installed filter behavior, physical
output, or transaction safety. R1/R2 still prohibit `--apply`.

At `be6842b`, review findings R1/R2 received a source-level transaction
remediation. Every scheduler query, queue mutation, disable/reject action, and
removal now uses one endpoint discovered under a controlled environment,
accepted only as a reachable root-owned local Unix socket, passed explicitly to
the CUPS command, and recorded in the protected intent. Client endpoint
overrides are rejected. Queue absence is derived only from a successful complete
inventory; query failure is distinct. The root namespace is rechecked after
interactive authorization and reserved atomically, then an eight-field intent
record precedes filter/queue mutation. Recovery verifies current ownership,
removes and rechecks the queue before touching the exact-hash filter or record,
uses noninteractive authorization, and reports residual state on conflict or
failure. INT/TERM/HUP feed the same EXIT recovery path; uncatchable termination
has a narrow documented manual route. Behavioral harnesses inject lost responses
at each mutation, cleanup/auth/query failures, changed URI, pre-existing
resources, altered/partial state, and TERM. The read-only Tahoe preflight
selected `/private/var/run/cupsd` and confirmed the experiment namespace absent.
Repository checks and 53 Python tests pass; the complete offline suite remains
green with 93 LabelCore tests. This addresses R1/R2 at source/harness level only.
`--apply` and `--remove` remain NOT RUN pending review and exact-head CI, so
scheduler acceptance is not claimed.

At `01406ca`, review findings R3/R5 received portable correctness fixes.
`BoundedDelivery` now validates the tracker's initial state and, for prepared
labels, the exact bound payload before the first sink call. Reusing a transmitted
tracker, delivering through an unprepared tracker, or substituting equal-length
bytes therefore produces zero external writes. Accepted-byte totals may only
increase. The byte-sink contract now explicitly excludes transports whose thrown
errors cannot establish that the current call accepted zero bytes; those require
the separate uncertain-attempt state. Both monochrome conversion paths now index
`Data` relative to its actual `startIndex`, with regressions proving sliced and
rebased buffers match. Focused tests pass 29 cases; complete debug and release
LabelCore suites pass 97 cases. The complete offline accelerator also passes 53
Python checks, 132 independent round trips, 15 backend ABI cases, ten filter ABI
cases, and one inert pipeline case. This closes the reviewed R3/R5 defects at the
portable automated-test level; it does not establish live transport, scheduler,
or physical-printer behavior.

At `e700f2c`, review finding R4 received a native transport-concurrency fix.
One serial attempt state machine now owns connection start, send admission,
timeout, task cancellation, connection termination, send completion, and final
settlement. The send call occurs on that serialized boundary immediately after
admission, eliminating the stale split-lock classification that could previously
report a retryable pre-send timeout after send had begun. Cancellation before
send becomes an explicit cancelled-before-transmission receipt; cancellation or
timeout after admission is uncertain and cannot authorize automatic replay.
Deterministic semaphore-barrier regressions enqueue timeout and cancellation
while the admitted send is paused, and a real loopback task proves Swift task
cancellation enters the state machine. The cancellation test passed five
repeated focused runs; complete LabelMac debug and release suites each pass 43
tests. This closes R4 at native automated-test level only. Network-framework
loopback does not establish a printer receipt, production endpoint reliability,
USB behavior, or physical output.

At `f1e2976`, review finding R9 and the remaining empty-annotation-array gap
received focused fixes. Installed speed, darkness, and tracking readings are now
named observations and are excluded from the job/default precedence chain.
Consequently, learning a device value cannot emit an otherwise unrequested
command or make a leave-unchanged job fail. Explicit documented speed remains
available; explicit darkness and tracking remain rejected until their commands
and installed-media semantics are qualified. The native annotation check now
rejects only a nonempty `/Annots` array: a synthetic empty-array page renders its
content, while the concrete interactive form fixture still rejects. Core debug
and release suites pass 98 tests; native debug and release suites pass 44 tests.
This closes R9 and the identified annotation edge case at automated-test level,
without claiming observed printer settings, application capture, or physical
output have been validated.

At `6fcb63e`, M2 gained a reusable offline release benchmark with unit-tested
macOS timing parsing and explicit nearest-rank percentile semantics. A clean
worktree run on Apple Silicon MacBookPro18,3, macOS 26.6.2, Xcode 26.6 used the
fixed native-vector fixture and version-1 4×6/8-dots-per-mm ticket for one cold
and twenty separate warm CLI/worker processes. Output remained 813×1219 dots
and 248,814 bytes. Cold time was 120.850 ms; warm median was 118.812 ms, warm
p95 was 123.138 ms, and maximum warm command RSS was 14,106,624 bytes. This
passes the proposed under-500-ms and under-256-MiB engineering targets and
records M2-AC12 for the offline scope. The committed evidence explicitly does
not cover scheduler overhead, USB transfer, printer mechanics, first-label time,
sustained physical rate, or release regression budgets.

At `3ad4bf0`, the clean exact head passed the complete local macOS CI-equivalent
sequence: 56 Python tests, 98 LabelCore tests in each configuration, 132
independent ZPL/PBM/analytic round trips, 15 backend ABI cases, ten filter ABI
cases, one inert pipeline case, and 44 LabelMac tests in each configuration.
The named test and oracle mapping is recorded in
`docs/validation/M2-AUTOMATED-CORE-2026-09-15.md`; it closes M2-AC01, M2-AC02,
M2-AC04, M2-AC05, M2-AC06, M2-AC09, and M2-AC13 at automated level only.
M2-AC03/07/08/10/11 remain open for their prescribed integration, compression,
ownership, filter, or physical evidence. No scheduler, printer, transport, or
system configuration was accessed by this validation.

At `7ee78db`, a conservative M3 audit plus an exact-head local rerun closed four
portable acceptance rows. All 98 LabelCore tests passed, including typed
capability/evidence distinctions, rejection of every unqualified baseline
request, exact safe control output, immutable prepared-label snapshots, and the
GC420d USB/direct-thermal/tear-off negative-option matrix. The eight focused
native raw-TCP tests also passed but were not used to claim installed transport
acceptance. `docs/validation/M3-AUTOMATED-CONTROLS-2026-09-15.md` records
M3-AC01, M3-AC02, M3-AC04, and M3-AC13 as automated passes. Full command
coverage, network fault completeness, USB, cross-process integration,
scheduler-visible uncertainty, privacy/status framing, and physical behavior
remain open at their prescribed evidence levels.

At `306bb32`, M4.1 gained a bounded immutable extraction profile and planner
instead of a parallel placeholder. It reuses `NormalizedRect`, `PDFPageBox`,
and `LabelOrderPlan`; keeps expected input-sheet geometry separate from named
output stock; permits only uniform fit; maps regions through the canonical
origin/rotation transform; preserves an explicit global label order through
collated/uncollated expansion; and requires every source page to be extracted
or explicitly reported as a non-label skip. Changed Letter/A4 geometry,
missing/unaccounted pages, duplicate identifiers/orders, invalid copy policy,
and count overflow fail before rendering or delivery. The full offline
accelerator passes with 104 LabelCore and 56 Python tests. This is partial
M4-AC01/02/03/04/05/13 evidence only; no M4 acceptance row is checked until
reference workflows, validators, native rendering/preview, import, UI, queue,
browser, and physical evidence satisfy their exact criteria.

At `4977e67`, the initial named workflow set binds native 4x6, Letter, and A4
application-facing geometries to the same nominal GC420d 4x6 stock without
inventing carrier crops. Native 4x6 has a validated full-page plan. Letter and
A4 are explicitly `requiresTeachOnce` and cannot yield regions, bitmaps, or
payloads until a reviewed profile exists. Input widths remain distinct at
101.6, 215.9, and 210 mm, and native rejects a Letter page. Four focused tests
and all 108 LabelCore tests pass. This adds partial M4-AC01/04/13 evidence only;
structural matching and profile persistence remain the next portable work.

At `60c1551`, extraction rules gained bounded local structural-anchor
validation without making analysis output a print source. Observations contain
only typed anchor kinds and normalized rectangles, not decoded barcode data.
Analysis-not-run, observed no-match, shifted layout, and competing candidates
fail distinctly before a plan exists. A successful match still derives the
render rectangle from the original page box and immutable profile region. The
full accelerator passes with 112 LabelCore and 56 Python tests. This is partial
M4-AC04/07 evidence; profile persistence and native fixture-backed analysis are
still required.

At `73a881d`, M4 gained an exact version-1 workflow-profile JSON contract with
a non-raisable 256 KiB cap and explicit allowlists at every object level. It
round-trips typed regions, rotations, page policies, stock, revisions, and
structural anchors while rejecting malformed/oversized input, unknown schema,
wrong or out-of-range numeric types, unsupported enums, and every unknown
field. Regressions explicitly attempt raw-command, filesystem-path, and
embedded-document fields at top-level and nested locations. The full
accelerator passes with 116 LabelCore and 56 Python tests. This closes M4-AC08
at automated level only; UI storage/import interaction and later migrations are
not claimed.

At `69dd2f5`, M4 connected immutable planned regions to the native Core
Graphics path. The renderer re-derives and verifies geometry from the original
PDF, selects the canonical upright region, applies only physical uniform fit,
and draws vectors directly into the final dot canvas. It handles all four
right-angle output rotations and a source page with `/Rotate 90`, rejects stale
plan geometry, output-stock mismatch, and unbounded transforms, and creates its
PBM preview from the exact packed bitmap passed to the encoder. Six focused
native tests and the complete debug/release CI-equivalent sequence pass. This
closes M4-AC02 and M4-AC07 at automated level; native analysis generation, UI,
application/browser capture, scheduler integration, and physical output remain
unverified.

At `5ae58ea`, M4 gained a bounded offline structural-border analyzer. A private
aspect-correct Core Graphics analysis raster feeds portable deterministic line
and border detection with hard input, pixel, feature, candidate, and work
ceilings. It returns typed normalized anchors only and cannot become final
render input. Five focused portable tests cover exact coordinates, broken
borders, padded/sliced data, invalid inputs, and work exhaustion. Three native
tests use the committed Letter and changed-layout fixtures: the original
profile matches, while the shifted fixture fails with the exact missing-anchor
reason before planning. The full CI-equivalent sequence passes 121 LabelCore
and 53 LabelMac tests in both configurations. This closes M4-AC04 at automated
level. The analyzer currently recognizes borders only; confirmation/qualification
state, candidate discovery UI, installed offline behavior, queues, browsers,
and physical output remain open.

At `b3b2a32`, M4 added an explicit unattended-workflow qualification boundary.
Parsing or structurally matching a profile now yields `confirmationRequired`
unless an explicit user-confirmation operation produced a qualification for the
exact immutable profile value. Every page must have structural checks before it
can be qualified; imported JSON cannot carry qualification state; revision or
geometry changes require confirmation again; and geometry/anchor mismatches
fail before qualification is considered. Five focused tests and all 126
LabelCore tests pass. This is partial automated M4-AC09/M4-AC12 evidence only:
durable local storage, UI confirmation, installed offline operation, queue
binding, and recovery still require their prescribed integration evidence.

At `df06929`, M4 added a private native profile store with immutable revisions
and separately persisted unattended-use qualification. Profile identifiers are
hashed rather than used as paths. Owner-only no-follow directories,
descriptor-relative regular-file reads, exclusive temporary files, complete
writes, file/directory `fsync`, and exclusive atomic rename prevent partial or
silent replacement. Concurrent conflicting writers leave one complete winner;
same-byte saves are idempotent. Import/save alone cannot create qualification,
which binds the exact canonical profile digest and fails closed on missing,
changed, malformed, or tampered state. Six focused tests and the complete
CI-equivalent sequence pass with 126 LabelCore and 59 LabelMac tests in both
configurations. This is partial M4-AC06/08/09/12 evidence; editor UI, container
selection, installed identity, queue binding, and restart recovery remain open.

At `05eb16d`, M4 gained portable teach-once draft state over the immutable
profile contract. Canonical normalized region/rotation edits create a new
revision, global reorder spans source pages, invalid edits are nonmutating, and
revision overflow fails. A three-region/two-page draft survives exact JSON
save/reopen and plans two collated copies as B,A,C,B,A,C; the shared planner
also retains its uncollated and explicit non-label-page oracles. Four focused
draft tests and all 130 LabelCore tests pass. This closes M4-AC03 and M4-AC05
at automated level and adds partial M4-AC06 evidence only. Rendered native
editor controls, keyboard operation, exact-preview presentation, and installed
save/reload interaction remain open.

At `7c5e58b`, M4 gained reusable native SwiftUI teach-once components and a
main-actor editor model. The view exposes explicit millimeter geometry,
right-angle rotation, global ordering, keyboard shortcuts, distinct input/output
media summaries, accessible errors, and separate save versus unattended
approval. Preview planning consumes analyzed original-page geometry and renders
the original PDF through the exact packed bitmap/encoder path. Four native tests
prove black/white region correction changes packed bytes, invalid edits are
nonmutating, save/approval stay separate, and reload creates the next revision.
The complete CI-equivalent sequence passes 130 LabelCore and 63 LabelMac tests
in both configurations. This is partial M4-AC01/06/09/12 evidence only: the
components still need a signed setup-app host, document-open flow, hands-on
keyboard/accessibility evidence, queue binding, and installed recovery proof.

At `75c2aee`, M5 gained its first native SwiftUI app host and a bounded local
PDF-open path. Native 4x6 pages become full-page drafts without requiring an
artificial border; Letter and A4 pages use the existing bounded structural
analyzer; ambiguous two-label sheets, mixed page geometry, unexpected pages,
and over-cap documents fail before a draft is created. The app reuses the M4
editor, immutable profile store, original-PDF renderer, and exact packed
preview, while save and unattended approval remain separate. Seven focused
bootstrap tests and the complete CI-equivalent sequence pass with 130 LabelCore
and 70 LabelMac tests in both configurations. The release app bundle is thin
ARM64 with macOS 26.0 minimum, explicitly labeled local-ad-hoc, and verified
after signing both its executable and containing bundle. An explicit future
Developer-ID selection fails before build/signing rather than downgrading.
This closes M5-AC12 at automated level only. The app has not been installed or
launched for hands-on UI, accessibility, quarantine, helper, scheduler,
restart, or physical-printer acceptance.

At `349731e`, the setup app gained a conservative reference-printer setup
surface derived from the typed GC420d profile. It distinguishes reported
USB/stock/tear-off facts from an unobserved stable device identity, exposes
only the documented 2/3/4 inches-per-second choices, and labels that choice as
an unsaved session draft that changes no printer setting. Cutter is unavailable
for this setup; peeler, darkness, and installed tracking remain explicitly
unknown or unqualified. Stock and tear-off confirmation gate local workflow
editing, but queue installation stays unavailable because no device identity
was discovered. Four focused tests and the complete CI-equivalent sequence pass
with 130 LabelCore and 74 LabelMac tests in both configurations. The signed app
also launched as a normal process and quit cleanly. UI automation could not
start on this host, so visual layout, keyboard traversal, VoiceOver, discovery,
saved defaults, install, scheduler, restart, and hardware behavior remain
unverified; no M5 acceptance row is newly closed by this slice.

At `d502d49`, M5 gained a portable virtual-queue definition. Each queue binds
the exact immutable workflow and printer profile schema/revision/digest, uses a
deterministic scheduler-safe name, and targets an opaque physical-device
coordination digest shared by every workflow for that device. Version 1 admits
only direct-thermal, tear-off, and an optional speed already validated by the
bound printer profile; it rejects unqualified controls, unknown fields, paths,
raw commands, document payloads, duplicate identities, and oversized data. Six
focused tests and the complete CI-equivalent sequence pass with 136 LabelCore
and 74 LabelMac tests in both configurations. This is partial automated
M5-AC04/05/07 evidence only. No queue was created, no administrator path ran,
and scheduler defaults, unrelated printers, restart recovery, system-dialog
propagation, installed serialization, USB delivery, and physical output remain
unverified.

At `ff0f2dc`, M5 gained private immutable storage for virtual-queue intent.
Saving or loading a queue reopens the exact workflow schema/revision/digest and
requires the separate user qualification for that exact value. It also checks
the printer schema/revision and a caller-supplied exact printer digest; a future
trusted printer-profile store still needs to own that digest. Owner-only
no-follow directories, bounded regular-file reads, complete writes, file and
directory `fsync`, and exclusive atomic rename make same-byte publication
idempotent and different-byte publication a conflict. Five focused tests cover
reference mismatch, missing qualification, tampering, unsafe roots, and
concurrent conflicting writers. The complete CI-equivalent sequence passes 136
LabelCore and 79 LabelMac tests in both configurations. This is additional
partial automated M5-AC05/07 evidence only. Active-revision selection,
scheduler publication, install/update/restart recovery, unrelated printer and
default preservation, and cross-queue delivery remain unverified.

At `87c7e8c`, the typed printer profile gained an exact bounded private JSON
contract. It preserves capability evidence, installed observations, media and
calibration, transport, and private stable connection identity while public
identity descriptions remain redacted. Deterministic ordering and exact keys
make the bytes suitable for immutable digest binding; malformed observations,
invalid evidence, unknown fields, duplicate speeds, bad types, and size-limit
violations fail closed. Five focused tests round-trip both the GC420d reference
and a fully observed synthetic profile. The complete CI-equivalent sequence
passes 141 LabelCore and 79 LabelMac tests in both configurations. This is
partial automated M3-AC01/13 and M5-AC05/07 evidence only. The immutable native
printer-profile store, real discovery/observation, active queue selection,
scheduler publication, USB delivery, and hardware validation remain open.

At `3fc7e58`, M5 gained a private immutable printer-profile store, and virtual
queues stopped accepting a free-standing printer digest from their caller. The
store hashes the canonical profile bytes and returns the exact reference used
by queue intent. Queue load reads that bounded reference from the same bytes,
resolves the exact stored profile, completes the full queue decode, and then
revalidates the qualified workflow. A shared owner-only descriptor-relative
primitive provides bounded no-follow reads, stable metadata checks, complete
writes, `fsync`, and exclusive atomic publication for printer profiles and
queue intents. Nine focused store/queue tests cover wrong digests, malformed
and tampered files, invalid identities, immutable and concurrent conflicts, and
exact round trips. The complete CI-equivalent sequence passes 141 LabelCore and
83 LabelMac tests in both configurations. This remains partial automated
M3-AC01/13 and M5-AC05/07 evidence: discovery, active revision selection,
scheduler publication, lifecycle recovery, USB, and hardware remain open.

At `087458d`, M5 gained a portable active-queue revision contract. An active
selection targets the exact immutable queue schema/revision/digest and records
a generation plus prior digest for a future compare-and-swap publisher. Initial
and later history invariants fail closed, as do unknown fields, embedded paths,
commands/documents, bad scalar types, and size-limit violations. Queue saves now
return their canonical immutable reference, and reference loads reject a wrong
digest, so a held job can retain its exact queue revision independently of a
later active selection. Four focused contract tests and updated queue-store
coverage pass; the complete CI-equivalent sequence passes 145 LabelCore and 83
LabelMac tests in both configurations. This is partial automated M5-AC05/07
evidence only. Native compare-and-swap persistence, crash recovery, scheduler
publication/rollback, held-job integration, restart behavior, and system state
preservation remain open.

At `aa11db9`, M5 gained private compare-and-swap persistence for that active
queue pointer. Each update resolves the exact immutable queue, printer, and
qualified workflow references, takes a per-queue descriptor-relative `flock`,
compares the complete expected selection, advances its generation/history, and
atomically replaces bounded canonical bytes with file and directory `fsync`.
Stale writers, fabricated digests, malformed or tampered bytes, unsafe storage,
and repeated revisions fail closed; a post-rename directory-sync failure is
explicitly uncertain rather than advertised as safe to retry. Four new focused
tests bring the queue/store group to nine tests and the complete CI-equivalent
sequence passes 145 LabelCore and 87 LabelMac tests in both configurations.
This is additional partial automated M5-AC05/07 evidence only. Scheduler
publication and rollback, held-job capture, UI defaults, restart repair,
uninstall, system-state preservation, and all administrator/hardware evidence
remain open.

At `d6c4130`, M3/M5 gained a bounded deterministic accepted-job ticket. The
ticket binds the exact immutable queue, workflow, printer profile, physical
device coordination digest, and active-selection generation; records source
identity and bounded intake provenance; makes final ordering and skipped pages
explicit; assigns copies, page ranges, extraction, orientation, and scaling to
exactly one owner; and snapshots fully resolved printer controls including the
media-geometry request. Full decode requires resolution of every exact immutable
reference and independently re-derives the output plan, so changed revisions,
ordering, ownership, unsupported controls, unknown fields, oversized data, and
overflowing copy expansion fail closed. Eight focused tests and the complete
CI-equivalent sequence pass with 153 LabelCore and 87 LabelMac tests in both
configurations. This is partial automated M3-AC02/12 and M5-AC05/07 evidence
only. The ticket is not yet a persistent accepted-job record or scheduler intake
boundary; held-job release, restart recovery, retention, system-dialog option
propagation, cross-process delivery, and all administrator/hardware evidence
remain open.

At `8bd8c32`, M3/M5 gained private immutable persistence for accepted-job
semantics. Save and load both re-resolve the exact queue, workflow, and printer
revisions and rerun complete ticket validation; canonical bytes and the
requested acceptance identity must match. Acceptance IDs are hashed on disk,
same-byte saves are idempotent, and different or concurrent bytes conflict
without replacing the winner. A focused regression advances the active queue
to a later immutable revision and proves the accepted ticket still reloads its
earlier queue and generation. Five focused tests and the complete CI-equivalent
sequence pass with 153 LabelCore and 92 LabelMac tests in both configurations.
This is partial automated M3-AC12 and M5-AC05/07 evidence only. The store holds
no source or rendered payload, and scheduler intake, source-spool ownership,
job-state/cancellation persistence, retention, restart recovery, publication,
delivery, and administrator/hardware evidence remain open.

At `e2b6332`, accepted-job persistence became an atomic ticket/source bundle.
The canonical resolved ticket and its exact original PDF bytes are fully
written and synchronized in an owner-only temporary directory before one
exclusive directory rename publishes the pair. Source count and digest are
checked before publication and on every load, exact immutable references are
re-resolved, and owner-only no-follow directory plus regular single-link file
checks constrain reloads. Injected failures at three pre-commit boundaries
leave no visible or temporary bundle; a failure after rename reports an
uncertain commit while preserving a complete recoverable bundle. Nine focused
tests and the complete CI-equivalent sequence pass with 153 LabelCore and 96
LabelMac tests in both configurations. This is additional partial automated
M3-AC12 and M5-AC05/07 evidence only. Descriptor-bound scheduler intake,
job-state/cancellation persistence, retention and deletion policy, held-job
release, restart recovery, cross-process delivery, and all administrator and
hardware evidence remain open.

At `ac6a178`, M3 gained a bounded canonical accepted-job state contract.
Accepted, prepared, waiting, transmitting, transmitted, device-confirmed,
uncertain, failed-before-transmission, and cancelled-before-transmission remain
distinct. Prepared and later states bind one payload digest and length; byte
progress cannot move backward, a transmitted job is not device-confirmed, and
uncertainty is terminal. Each update increments a generation and names the
prior canonical record digest so a future compare-and-swap store can reject
stale writers and broken histories. Six focused tests and the complete
CI-equivalent sequence pass with 159 LabelCore and 96 LabelMac tests in both
configurations. This is partial automated M3-AC09/12 and M5-AC07 evidence only.
Persistence, cancellation-token authorization, scheduler result mapping,
restart recovery, and all installed/hardware evidence remain open.

At `fc2c8de`, accepted-job state became private compare-and-swap persistence.
The initial canonical accepted record is part of the same exclusive directory
publication as the ticket and original PDF. Later updates take a per-job
cross-process lock, compare the complete expected record, bind the next
generation to the exact prior canonical digest, and atomically replace the
owner-only state file. Concurrent writers have one winner; post-rename failure
is uncertain and recoverable. Cancellation is a separate operation whose
bounded raw capability must hash to the ticket's stored digest using
constant-time comparison; ordinary transitions cannot forge cancellation, a
wrong capability has zero state effect, and raw capabilities are not persisted.
Fourteen focused tests and the complete CI-equivalent sequence pass with 159
LabelCore and 101 LabelMac tests in both configurations. This is additional
partial automated M3-AC09/12 and M5-AC07/09 evidence only. Scheduler intake,
prepared-artifact integration, scheduler retry mapping, restart recovery,
retention/deletion policy, and all installed/hardware evidence remain open.

At `acf11ab`, M3 gained a complete ordered prepared-job payload contract. The
contract requires exactly one typed production-encoder result per resolved
output label, preserves that order, requires one immutable printer-profile
snapshot across every label, rejects empty labels, and preflights the aggregate
64 MiB bound before concatenation. Direct public construction of individual
prepared labels is removed, narrowing public creation to the typed encoder.
Seven focused tests and the complete CI-equivalent sequence pass with 163
LabelCore and 101 LabelMac tests in both configurations. This is partial
automated M3-AC02/09 and M5-AC07 evidence only. Persistent artifact publication,
the accepted-to-prepared atomic boundary, real multi-page rendering, scheduler
intake, delivery, and all installed/hardware evidence remain open.

At `9dfe442`, prepared output became a durable, state-authorized artifact. The
typed payload now binds each encoder result to the exact resolved output
identity and preserves the resolved controls used to generate its bytes.
Publication verifies output order, controls, and the immutable printer snapshot
against the accepted ticket, then synchronizes an exclusive owner-only
`prepared.zpl` before atomically advancing `accepted` to `prepared` with its
exact digest and count. Digest-only preparation through the general state API
is rejected. Pre-state faults leave an inert exact-retry-only orphan; different
bytes conflict. Post-state-rename failure is uncertain and recoverable. Every
payload-bearing read and later transition revalidates the artifact, including
regular-file, owner, mode, link-count, stable-metadata, size, and digest checks.
Seven core and eighteen store-focused tests plus the complete CI-equivalent
sequence pass with 163 LabelCore and 105 LabelMac tests in both configurations.
This is additional partial automated M3-AC02/09/12 and M5-AC07/09 evidence only.
Scheduler intake, real multi-page preparation orchestration, held-job release,
delivery/result mapping, restart enumeration, retention/deletion policy, and
all administrator/hardware evidence remain open.

At `8a7fef8`, the imaging decision became part of the immutable job contract.
Workflow schema 2 requires the exact monochrome policy and parameter; accepted
ticket schema 2 copies it and rejects divergence from the referenced workflow.
Prepared payload publication also requires the ticket policy before it can
create an artifact, and verified prepared loads return that binding. The native
editor no longer carries an independent conversion default: exact-bitmap
preview uses the draft profile's policy. Legacy schema-1 workflow/ticket bytes
fail closed instead of acquiring a guessed threshold. The complete
CI-equivalent sequence passes with 164 LabelCore and 105 LabelMac tests in both
configurations. This is additional partial automated M2-AC05/09, M3-AC02/12,
M4-AC06/09, and M5-AC07/09 evidence only. Explicit pre-release profile
recreation, real accepted-job rendering, scheduler intake, installation,
transport, and all physical evidence remain open.

At `c9a652e` plus review remediation `92606bb`, the M1 discard transaction
closes the remaining competing-
invocation rollback defect identified as R10. Automatic rollback is enabled
only after this invocation successfully reserves the protected root and then
requires the exact random transaction identifier from its protected intent.
It cannot adopt a generic matching record. Catchable signals are deferred
across effective root creation until rollback eligibility is recorded, and
explicit recovery accepts only the exact current or immediately preceding
record shape. A queue found by the late absence
check, or one left after an ambiguous queue-create result, is retained with
the filter and intent instead of being deleted. Explicit `--remove` remains a
separate record-validated recovery operation. Four contention regressions join
the existing mutation-boundary and signal harness. The complete local
CI-equivalent sequence passes with 62 Python, 164 LabelCore, and 105 LabelMac
tests in both configurations, plus 132 independent round trips, 15 backend ABI
cases, 10 filter ABI cases, and one inert pipeline case. This is source-level
M1 transaction safety evidence only. No administrator authorization, queue,
protected path, scheduler job, system setting, or printer was changed; all M1
integration acceptance remains open.

At `9019eb6`, the final PR #30 review findings were addressed conservatively.
Because the scheduler create operation can also modify an existing destination,
neither command success nor matching URI readback is treated as exclusive queue
acquisition. Automatic rollback now retains any present queue and its protected
recovery evidence; only explicit record-validated recovery may remove it. New
regressions cover a successful create-or-modify race and TERM during queue
readback, with zero destructive action against the ambiguous queue. The Python
suite now has 64 passing tests. No administrator authorization, queue, protected
path, scheduler job, system setting, or printer was changed.

At `88fb87e`, bounded ingestion closes review finding R14. All prospective
regular-file reads use one shared nonblocking, no-follow descriptor-open rule
before validating type, owner, link count, permissions, size, and stable
metadata. This covers path-based CLI PDF/ticket input and descriptor-relative
state, prepared-payload, workflow, printer-profile, queue, and active-selection
records. Native subprocess regressions impose a two-second hard deadline on
FIFOs with and without a writer; separate real CLI cases verify FIFO PDF and
ticket rejection before worker startup. Local validation passes with 60 Python,
164 LabelCore, and 107 LabelMac tests, plus the complete offline accelerator
suite. This is partial automated M2-AC09/10 and M3-AC09/12 evidence only. It is
not scheduler intake, installed-spooler, transport, or physical-printer
evidence, and no system or printer state changed.


At `9019eb6`, the final PR #30 review findings were addressed conservatively.
Because the scheduler create operation can also modify an existing destination,
neither command success nor matching URI readback is treated as exclusive queue
acquisition. Automatic rollback now retains any present queue and its protected
recovery evidence; only explicit record-validated recovery may remove it. New
regressions cover a successful create-or-modify race and TERM during queue
readback, with zero destructive action against the ambiguous queue. The Python
suite now has 64 passing tests. No administrator authorization, queue, protected
path, scheduler job, system setting, or printer was changed.

At `5a1d04a`, review finding R11 is closed at the native persistence boundary.
Lifecycle state schema 2 names the digest of the exact canonical accepted
ticket, and `AcceptedJobStateStore` is constructed from a stable
descriptor-backed `AcceptedJobStore` capability. Ticket authorization, state
comparison, prepared-artifact validation, and mutation now occur under the same
locked bundle descriptor. Cross-store tests prove that two valid repositories
sharing an acceptance identifier cannot lend cancellation tokens or expected
states to one another, and a path-replacement test proves that a bound store
cannot be redirected to a new repository at the old pathname. Local validation
passes with 64 Python, 164 LabelCore, and 109 LabelMac tests, including 20
focused lifecycle tests. Review remediation `8a3ef38` additionally migrates
canonical schema-1 lifecycle records only under the descriptor-bound bundle
lock after binding them to the verified ticket digest. Waiting jobs remain
cancellable, and transmitting or uncertain jobs retain exact byte progress.
The complete local sequence now passes with 64 Python, 165 LabelCore, and 111
LabelMac tests. R12 and R13 remain open; no scheduler, transport,
administrator, or hardware path was exercised.

At `1e51a8b`, review finding R12 is closed at the accepted-bundle publication
boundary. An identical save retry now repeats the accepted-jobs parent-directory
sync before acknowledging success; sync failure remains `commitUncertain` even
when exact bytes are visible. Regressions inject that actual barrier, cover
persistent failure and later recovery, pause one writer between rename and sync
while a duplicate writer confirms durability, and prove that retries never
reset an already-prepared lifecycle record. Local validation passes with 64
Python, 165 LabelCore, and 114 LabelMac tests, including 25 focused store tests.
This does not claim universal power-loss persistence, scheduler acceptance, or
hardware evidence.

At `f42226d`, review finding R13 is closed at the immutable configuration-store
boundary. Workflow profiles, unattended qualifications, printer profiles, and
virtual queues share a publisher that distinguishes pre-rename failure from a
visible but durability-unconfirmed commit. The latter carries the exact ID,
schema, revision, and canonical digest. Identical retries repeat the real
directory barrier; conflicts remain conflicts. Fault injection proves no final
record before rename, persistent uncertainty after rename, exact-byte recovery,
and later successful reconciliation. The complete local sequence passes with
64 Python, 165 LabelCore, and 119 LabelMac tests in debug and release. The
R10-R14 source findings are now addressed, but review and hosted exact-head CI
remain separate gates. No administrator, scheduler, transport, or hardware path
was exercised.

Review remediation `f4bb7f8` extends that durability boundary to the stable
store root. Every successful immutable publication now syncs both the category
directory containing the renamed record and its parent store directory. A
targeted fault test proves that successful category sync followed by failing
root sync returns exact commit uncertainty, leaves recoverable bytes, and
requires an identical retry to complete both barriers. The complete local
sequence passes with 64 Python, 165 LabelCore, and 120 LabelMac tests in debug
and release. This remains host-filesystem barrier evidence, not an
unconditional device-level power-loss claim.

Second-pass review remediation `c4798ef` completes the pathname publication
boundary. After syncing the record category and store root, publication reopens
the root through its containing directory, verifies the inode matches the
already validated root descriptor, and syncs that containing directory before
success. Exact visible bytes are now reconciled before fallible temporary-file
staging, so an ambiguous retry cannot be downgraded by a redundant staging
failure. Two targeted regressions cover both cases; LabelMac reaches 121 tests
in debug and release on the PR #34 stack.

At `c2e6e53`, M3 gains its first connected persisted-delivery path while
remaining deliberately inert. It reloads the exact accepted ticket and
prepared artifact, acquires the common physical-device lease, persists
zero-byte transmitting intent before any discard-sink action, advances bounded
monotonic byte progress, and records transmitted versus zero/partial uncertain
outcomes. Lease contention and invalid or repeated attempts have no sink side
effects. Seven new regressions bring LabelMac to 127 tests in debug and release;
the complete local sequence remains green with 64 Python and 165 LabelCore
tests. This is partial automated M3-AC05/07/08/09/12 evidence only. No CUPS,
TCP, USB, daemon, scheduler retry mapping, administrator path, or printer was
used, so all prescribed integration and hardware rows remain open.

Follow-up `297c6aa` removes the remaining caller-selected lease identity from
that path. `StoredPreparedJob` now carries the physical-device coordination ID
from the verified immutable ticket, and delivery derives its lock identity only
from that value before acquiring the lease. The existing contention regression
now holds the ticket-bound domain, proving that delivery cannot select an alias
to bypass the shared boundary.

Review remediation `e977b33` closes the two remaining first-pass findings. A
job durably left in `waiting` can resume because no sink action is permitted
before the subsequent transmitting-intent commit, while the ticket-derived
lease excludes a still-live prior owner. Lease contention is now explicitly
retryable because it changes neither lifecycle nor sink. The focused suite has
33 passing accepted-job tests and the complete LabelMac suite has 128 tests.
After merging PR #34 remediation `c4798ef`, exact combined head `9401b39`
passes 64 Python, 165 LabelCore, and 129 LabelMac tests in debug and release,
plus all independent oracle, ABI, inert-pipeline, and local-signature checks.

Second-pass review remediation `7929944` aligns pre-send retry classification
with durable lifecycle state. A fault before transmitting intent now reports
the retryable `failedBeforeTransmission` outcome while leaving the job in
`waiting`; it no longer writes a terminal state that rejects the advertised
retry. The regression retries the same acceptance ID and reaches
`transmitted`, with no first-attempt sink action. The focused accepted-job
suite passes all 33 tests.

At `5a34971`, the previously separate intake, rendering, preparation, and inert
delivery components gain one synthetic connected path. It reads an already
opened PDF with bounded descriptor-relative `pread`, so pathname replacement
cannot redirect the accepted bytes or alter the caller's file offset. The path
resolves the active immutable queue/profile chain, rejects layout and
unexpected-page mismatches before acceptance, persists the exact original PDF,
renders each planned region at the documented GC420d 8 dots/mm reference
pitch, publishes the complete typed prepared payload, and reaches only the
persisted in-memory discard delivery. A committed vector PDF completes through
`transmitted`; a multi-page mismatch publishes no accepted bundle. Three new
tests bring LabelMac to 132 tests in debug and release. This is synthetic
automated evidence only: no installed scheduler, production worker deadline,
IPC identity, transport, USB, administrator path, or printer is proven.

First-pass review remediation `6e11d16` makes that path bounded and genuinely
retryable. Per-label encoding now receives only the remaining portion of the
64 MiB job budget, so a large valid plan cannot eagerly retain gigabytes before
the aggregate check. Exact accepted-bundle lookup distinguishes absence from
an unsafe present record; prepared/waiting retries validate the source and
cancellation capability, repeat the durability barrier, reuse the stored
payload, and remain bound to the accepted queue even after active selection
changes. The workflow stock must also match the profile's observed loaded face
before acceptance. Five new regressions bring LabelMac to 137 tests in debug
and release. The complete exact-head gate also passes 64 Python, 165 LabelCore
debug/release, 132 independent round trips, all ABI/inert-pipeline checks, and
local ad-hoc product signature verification.

Second/final review remediation `887ddf5` preserves terminal delivery evidence
across a lost caller response. Exact re-entry into a persisted `uncertain` job
validates the immutable prepared artifact and returns the recorded accepted-byte
count without invoking delivery; persisted `transmitted` state is likewise
returned without a second sink pass. Re-entry also requires the ticket's queue
ID. Two regressions bring the focused/debug LabelMac suite to 139 tests; the
complete exact-head gate also passes 64 Python tests, 165 LabelCore tests in
debug and release, all 139 LabelMac tests in debug and release, 132 independent
round trips, all ABI/inert-pipeline checks, and local ad-hoc product signature
verification. Per the two-pass policy, no third review will be requested.

At `65dce21`, the first restart-recovery primitive reconciles one known
accepted-job ID without adding scheduler or printer I/O. It validates the exact
prepared artifact and acquires the same ticket-derived physical-device lease
as delivery before converting an abandoned `transmitting` record to terminal
`uncertain`, preserving the last known accepted-byte count. A held lease leaves
state unchanged; prepared/waiting jobs remain merely ready, and terminal
transmitted/device-confirmed/uncertain evidence is read without replay or
mutation. Four regressions bring LabelMac to 143 tests in debug and release.
The complete exact-head gate also passes 64 Python tests, 165 LabelCore tests in
debug and release, 132 independent round trips, all ABI/inert-pipeline checks,
and local ad-hoc product signature verification. This is partial automated
M3-AC09 evidence only: installed restart discovery, worker IPC, scheduler retry
mapping, transport, USB, and physical output remain unverified.

First-review remediation `75fca07` closes the ready-to-transmitting race. A
deterministic barrier advances the job after recovery's first read; the second
read now routes the observed transmitting state through the same physical-device
lease rather than returning an ownership-blind error. The focused recovery set
and all 144 LabelMac tests pass in debug and release. The exact-head complete
gate also passes 64 Python tests, 165 LabelCore tests in debug and release, 132
independent round trips, all ABI/inert-pipeline checks, and local ad-hoc product
signature verification. The second/final review is next.

Second/final review remediation `616a5d8` handles cancellation and pre-send
failure published between the same two reads. Recovery boundedly reloads the
monotonic lifecycle and returns the newer payload-free terminal outcome rather
than surfacing an avoidable invalid-state error. Two deterministic regressions
bring LabelMac to 146 tests in debug and release; the complete exact-head gate
again passes 64 Python tests, 165 LabelCore tests in debug and release, 132
independent round trips, every ABI/inert-pipeline check, and local ad-hoc
signature verification. Both permitted review passes are now reconciled; no
third review will be requested.

At `b45f93b`, restart discovery connects the pinned accepted-jobs directory to
the per-job recovery primitive. The bounded inventory verifies final hash names,
canonical ticket/source/state and immutable references, distinguishes owned
UUID staging directories from invalid artifacts, reserves cumulative source
read budget before ingestion, and checks declared prepared totals. The sweep
revalidates jobs independently in stable ID order and can reconcile a discovered
abandoned send without deletion or replay. Prepared reads now reject sizes
larger than their exact lifecycle binding before allocation. Six regressions
bring LabelMac to 152 tests in debug and release; the complete gate also passes
64 Python tests, 165 LabelCore tests in debug and release, 132 independent round
trips, all ABI/inert-pipeline checks, and local ad-hoc signature verification.
This is partial automated M3-AC09/12 evidence, not an atomic concurrent snapshot,
installed worker startup, scheduler mapping, retention/deletion, or printer pass.

PR #38 completed both permitted independent code-review passes cleanly at
`53c6b99`, with no inline findings. Hosted run `35069104708` passed that
same exact head by manual dispatch: repository preflight, macOS ARM, and
`ci-required` are green. Its log confirms the 64/165/152 suites, independent
oracle, ABI/inert-pipeline checks, and ad-hoc signatures. Stacked PRs do not automatically
trigger the workflow because its PR branch filter names only `main`.

The M1 read-only scheduler, filter-signature, and three pinned-PPD checks were
refreshed at `53c6b99`: all passed, with the experiment namespace absent and no
system state changed. Administrative apply/remove and held-job submission remain
NOT RUN; no scheduler or physical acceptance follows from these prerequisites.

At `79411af`, the CI pull-request trigger now covers stacked target branches,
while push builds remain restricted to `main`. The standard hosted runners,
read-only tokens, pinned actions, finite timeouts, cancellation, and fail-closed
aggregate remain unchanged. Repository preflight, 65 Python tests, 165 LabelCore
debug tests, and 152 LabelMac debug tests pass. Automatic PR #39 run
`35069832168` passed exact head `aaf8425` with repository preflight, macOS ARM,
and `ci-required` green; its log confirms 65 Python tests, 165 LabelCore and
152 LabelMac tests in debug and release, 132 independent round trips, all
ABI/inert-pipeline checks, and local ad-hoc signatures. This proves automatic
execution against a stacked target, not fork or deliberate-failure acceptance.
This configuration-only slice does not need
a separate correctness review or change printing behavior.

The M1 recovery guide now matches the reviewed `9019eb6` script boundary:
automatic rollback never removes a present queue, including after successful
create/readback, because queue creation is not exclusive. It retains all
recovery artifacts for explicit record-validated removal. This documentation
correction changes no script behavior and provides no new M1 integration pass.
Local repository preflight and 65 Python, 165 LabelCore debug, and 152 LabelMac
debug tests passed on the existing Tahoe host. Release tests are unchanged from
the preceding hosted run; they were not rerun for this documentation-only diff.

PR #40 automatic run `35070491708` revealed that the mandatory manifest update
caused native compilation even for a documentation-only diff. The scope
classifier now permits `MANIFEST.sha256` alongside only recognized documentation,
while manifest-only, code, workflow, unknown, and empty diffs still compile.
Repository preflight and 67 Python tests pass, including both new classification
regressions. This advances M0-AC06 implementation only; the hosted docs-only
skip/aggregate result remains to be proven after this classifier is available
in a PR base. No product code or scheduler behavior changed.

Classifier implementation `431f0d6` additionally passed 165 LabelCore and 152
LabelMac debug tests with pipe-failure propagation. The documentation-only
follow-up records the concrete manifest regression and supplies the intended
hosted skip/aggregate probe against that implementation branch. Its result is
now proven at exact `83aec67` by automatic PR #42 run `35070738539`:
repository preflight passed, native macOS skipped, and `ci-required` passed.
Its log confirms the false scope and skipped native aggregate inputs; Linux
ran 67 Python tests with one platform-specific skip. Deliberate-failure and
fork acceptance remain separate.

PR #41 full automatic run `35070667206` passed exact `431f0d6`; inspected logs
confirm 67 Python, 165 Core and 152 Mac tests in debug/release, 132 independent
round trips, every ABI/inert check, and ad-hoc signatures. PR #40 run
`35070491708` also completed successfully. The docs-only evidence head
`84ac6da` additionally passed run `35070883055` with native skipped and the
aggregate green. No installation or physical acceptance follows.

The isolated M0-AC06 probe at `11084e3` deliberately failed one Python test.
Automatic draft PR #43 run `35071242478` failed repository preflight and
`ci-required`, with native macOS skipped. Its log confirms the intentional
marker, test exit 1, and aggregate `REPOSITORY_RESULT=failure`; thus a failed
test does not produce a false green. Only the injected test was then removed.
Repository preflight and the normal 67 Python tests pass again. Hosted recovery
run `35071315857` passed exact `e464491` with native skipped and the aggregate
green; separate local Core 165 and Mac 152 debug tests passed. Both finite
M0-AC06 outcomes are now observed; fork/protection evidence remains separate.
No product, installation, scheduler, or printer
behavior changed; never merge the historical failing head.

The first administrator procedure is now explicitly limited to one held
synthetic PDF, one release, a 60-second observation deadline, and immediate
validated removal in `M1-SINGLE-JOB-ADMISSION.md`. It requires exact final filter
chain/URI verification before submission, brief acceptance while disabled,
immediate rejection, job-correlated filter metadata, and unchanged baselines.
It remains NOT RUN and grants no new privilege/device consent; broader M1
application/fidelity/restart/identity evidence stays open.

The isolated offline worker now rejects pre-cancelled bounded requests before
executable inspection/source staging and rechecks before child launch. A focused
regression preserves the distinct cancellation error; live-child termination
tests remain passing. The full local gate completed with 67 Python, 165 Core
and 153 Mac tests in debug/release, all independent oracle/ABI/inert checks,
and ad-hoc signatures. This is M2-AC09 evidence only, not atomic transport
arbitration or isolated-region integration into the synthetic pipeline.
PR #45 independent review completed cleanly at `cf379e8` against `42a4c80`.
Automatic hosted run `35071875026` passed the same exact head; inspected logs
confirm full 67/165/153 suites, all oracle/ABI/inert checks, and ad-hoc
signatures. No repeat review, merge, installation, or printer acceptance follows.

The existing isolated worker now accepts explicit extraction ticket schema 2:
upright normalized region, expected source rectangle, validated right-angle
rotation, and uniform fit. Schema 1 remains full-page only; unknown versions
remain rejected. Real-worker regressions prove exact direct/child region output,
rotation discrimination, and changed-source geometry rejection. The full local
gate passed 67 Python, 166 Core and 156 Mac tests in debug/release, all oracle,
ABI/inert cases, and ad-hoc signatures. Hosted CI/review and persisted-intake
connection remain pending; no scheduler or physical acceptance follows.

Synthetic intake now prepares each planned region through the bounded existing
worker, validates exact PBM dimensions/header/count/padding and regenerated
diagnostic encoding, then applies immutable production controls in the parent.
No in-process raster fallback remains. Full local validation passed 67 Python,
166 Core and 158 Mac tests in debug/release, oracle/ABI/inert checks, and ad-hoc
signatures. Ten focused tests passed. Page/structural PDF analysis remains
in-process, and deadlines are per child rather than whole-job. Hosted CI/review
and all scheduler/USB/installation evidence remain separate gates.

PR #46's extraction worker contract passed independent review and automatic
hosted run `35072850127` at exact `e8ae1fd`; inspected logs confirm the
67/166/156 debug/release suites, independent checks, and ad-hoc signatures.
PR #47's connected intake review completed cleanly at code head `38cef69`.
Automatic hosted run `35073499862` passed cumulative head `2e592f9` with all
three required jobs green. No scheduler or physical acceptance follows.

The next connected intake slice moves page-box/structural analysis into the
existing bounded child, with checked source-bound layout facts and explicit
output/anchor ceilings. Original bytes still feed final rendering. Focused
worker/layout/intake tests pass; the full local gate passed 67 Python, 166 Core
and 163 Mac tests in debug/release with all oracle/ABI/inert and signature checks.
Hosted run `35074656870` passed exact code head `67347e6`, with suite/signature
counts confirmed in logs; independent review completed cleanly at the same
head. Evidence is recorded
in `M3-ISOLATED-LAYOUT-ANALYSIS-2026-09-16.md`. Per-child deadlines are not a
whole-job bound, and installed scheduler/identity evidence remains open.

The shared preparation-budget slice uses one monotonic deadline for initial/retry
analysis and all label workers, with distinct processing interruption errors.
It does not renew time per label, manufacture persisted cancellation, or promise
to interrupt filesystem calls. Twenty-nine focused tests passed; the full local
gate passed 67/166/167 debug/release with all independent and signing checks;
hosted run `35075349804` and independent review passed exact code head `769f0c6`.
Counts/signatures were confirmed in logs. Evidence is recorded in
`M3-SHARED-PREPARATION-BUDGET-2026-09-16.md`.

The setup Preview button now runs original-PDF extraction in the bounded child
off the main actor, with cancellation and request/profile/selection-bound stale
result protection. Nine focused tests passed, including a completed-real-result
race. The app includes/signs the worker and requires a synthetic packaged-worker
equality smoke. Full local validation passed 67/166/172 debug/release, all
independent/inert checks, nested signatures and packaged-worker equality.
Hosted/review and all GUI evidence remain pending in
`M4-ISOLATED-EDITOR-PREVIEW-2026-09-16.md`. PDF opening/bootstrap remains
in-process; no scheduler or physical acceptance follows.


Setup document opening now moves bounded reading and original-PDF analysis off
the main actor, preserving failed/cancelled replacement drafts and rejecting
obsolete editor installation. The existing layout worker adds explicit capped
all-page analysis, and unchanged bootstrap builds unsaved profiles from checked
facts. Eighteen focused tests and the full local 67/166/178 debug/release gate
passed. Publication is deferred pending PR #50's genuine parent-death worker
supervision finding; its hosted CI is green but review is not clean. Evidence is in
`M4-ISOLATED-DOCUMENT-OPENING-2026-09-16.md`. Lifetime fix `6ff328a` is now
integrated locally at `26ee086`; the combined full gate passes 67/166/183 in
debug/release with independent checks, signatures and packaged-worker equality.
Publication remains held on PR #50's live second review/hosted CI. A finite
synthetic GUI checklist is prepared but unrun. GUI, security-scope policy and all
scheduler/privilege/device acceptance remain unverified.

PR #50's first independent review found that parent-only deadlines could leave
an orphaned native worker after app termination. The same-branch remediation
adds child-owned finite supervision and nonce/inode-bound scratch ownership with
shared writer locks and conservative bounded startup recovery. Five focused
native tests pass, including actual parent termination and independent timeout.
Full local validation passed 67/166/177 debug/release, independent oracle/ABI/inert
checks, ad-hoc signatures, and packaged-worker equality. Second review and hosted
exact-head CI remain pending; details and limitations
are in `M4-WORKER-LIFETIME-2026-09-16.md`. Hosted run `35076644936` passed the
earlier `77874a3` head but does not validate this remediation.

PR #50's second review completed at `6ff328a` with one genuine ancillary-recovery
failure issue. Recovery now returns a sanitized nonthrowing warning outside the
controller's setup initialization. Six focused native tests pass; full local
validation of this follow-up passed 67/166/178 debug/release with independent
checks, signatures and packaged-worker equality. The existing hosted run remains live;
it is not restarted or claimed terminal. No third review is requested.

Setup document opening now moves bounded reading and original-PDF analysis off
the main actor, preserving failed/cancelled replacement drafts and rejecting
obsolete editor installation. The existing layout worker adds explicit capped
all-page analysis, and unchanged bootstrap builds unsaved profiles from checked
facts. Eighteen focused tests and the full local 67/166/178 debug/release gate
passed. Publication is deferred pending PR #50's genuine parent-death worker
supervision finding; its hosted CI is green but review is not clean. Evidence is in
`M4-ISOLATED-DOCUMENT-OPENING-2026-09-16.md`. GUI, security-scope policy and all
scheduler/privilege/device acceptance remain unverified.

Document-opening local combined `bf9d21c` incorporates correction `5830f5b`.
The final full local gate passes 67/166/184 debug/release, all independent/ABI/
inert checks, ad-hoc signatures and packaged-worker equality. PR #50's two
findings are addressed and resolved. Its exact-head hosted run `35080048258`
remains live, so the opening slice remains unpublished. GUI inspection is
NOT RUN after the runtime startup failure; no installed acceptance follows.

At implementation `f9db898`, explicit manual PDF opening requests
bounded page geometry from the existing child, accounts for every page, and
creates full-page editable starting regions without guessed crops or structural
qualification. The default assisted path remains fail-closed. An edited-draft
regression exposed and corrected retained-decimal conversion in the shared
workflow codec, preserving exact identity instead of relaxing equality. Six
codec and 15 opening/bootstrap tests pass; full local validation passes
67/167/187 debug/release, all independent/ABI/inert checks, ad-hoc signatures
and packaged-worker equality. Hosted/review for this slice remain pending.
Details and unverified UI/source-selection gates are in
`M4-MANUAL-DOCUMENT-INTAKE-2026-09-16.md`.

Dependencies are verified: PR #50 run `35080048258` passed exact correction
`5830f5b` with 67/166/178 debug/release and signatures/equality confirmed in logs.
PR #51 first review completed cleanly at exact `ee36a34`; run `35080396474`
passed that head with 67/166/184 debug/release and all independent/signing checks.
No repeat review or merge follows. GUI and installed acceptance remain open.


The source-page-reference slice is connected locally to the editor. It reuses the
bounded original-PDF child and strict packed-output validator, labels display
pixels separately from exact print output, and overlays normalized bounds for
numerical/keyboard editing. Independent UUID/cancellation protects stale source
results and replacement opening. Four real-worker tests and combined `cdedc71`
full gate pass 67/167/192 debug/release, independent checks, signatures and
packaged-worker equality. Own hosted/review and parent's correction checks remain
pending. `M4-SOURCE-PAGE-REFERENCE-2026-09-16.md` records remaining GUI,
zoom and direct-selection gates. No installed or physical acceptance follows.

PR #52's first review identified fixed manual IDs preventing a second workflow
save. The same-branch correction assigns distinct IDs to new manual drafts and
preserves existing immutable records. Twelve focused bootstrap tests pass,
including two edited Letter/A4 workflows in one store and idempotent resave.
Full local validation passed 67/167/188 debug/release with all independent and
signing checks. Second review and new exact-head hosted validation remain
pending. Source-reference work is checkpointed locally
at `f1adeeb`; its full gate passed 67/167/191 debug/release with all independent
and signing checks, but publication waits for this dependency correction.

The source-page-reference slice is connected locally to the editor. It reuses the
bounded original-PDF child and strict packed-output validator, labels display
pixels separately from exact print output, and overlays normalized bounds for
numerical/keyboard editing. Independent UUID/cancellation protects stale source
results and replacement opening. Four real-worker tests pass; full validation
is pending. `M4-SOURCE-PAGE-REFERENCE-2026-09-16.md` records remaining GUI,
zoom and direct-selection gates. No installed or physical acceptance follows.

After each slice, record the actual commit SHA, acceptance IDs advanced, tests run,
results, remaining evidence gates and next safe action. Do not fabricate a repository
commit hash for this preparation archive or convert partial tests into full acceptance.

## PR2 merge preparation — finite extents

Source 2e56f2e3a38f80555cd6a81170adbfac97fe1f7a; [receipt](validation/M2-PR2-FINITE-EXTENTS-2026-09-17.md). Eight before-fix overflow acceptances reproduced; corner checks preserve negative origins across rotations/UserUnit.57Core both/native scaffold both/accelerator both/local-ad-hoc diagnostic and34Python/preflight passed. No scheduler/printer claim. Maintainer authorized merges through38; PR1 merged separately, native stack82 registered2–59. Next cascading rebase and exact-head hosted CI before further merges.

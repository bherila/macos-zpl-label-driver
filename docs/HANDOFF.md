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

After each slice, record the actual commit SHA, acceptance IDs advanced, tests run,
results, remaining evidence gates and next safe action. Do not fabricate a repository
commit hash for this preparation archive or convert partial tests into full acceptance.

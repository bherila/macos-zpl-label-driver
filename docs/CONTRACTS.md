# Shared contracts and invariants

Immutable configuration-store roots must name an ordinary final path component,
not reserved `.` or `..`. Reject those spellings before filesystem mutation rather
than silently normalizing them; this preserves the containing-directory barrier's
naming contract. The workflow/printer/virtual-queue APIs map rejection to their
existing unsafe-store-directory result. Stable provisioned ancestry remains the
caller's responsibility; root spelling is not recursive ancestry attestation.

These are normative design requirements. Implement the contracts incrementally; do not generate placeholder implementations that return success.

## Units, coordinates and geometry

Use named types for PDF points, physical millimetres/inches and printer dots. Conversion uses the actual profile resolution, which may be represented as dots/mm or rational dots/inch; do not silently equate marketing '203 DPI' with an exact dot pitch. Test non-square resolutions even if initial devices use square dots.

For profile editing, use normalized coordinates in the **visually upright effective page box**, origin top-left, x right, y down. Regions have x/y/width/height in [0,1], strictly positive size, and may not exceed bounds. A single tested transform converts these coordinates to original PDF user space, accounting for box origin, `/Rotate`, supported `/UserUnit` and clipping. Do not apply PDF rotation twice. Unsupported geometry fails explicitly.

The native effective page box is the intersection of CropBox and MediaBox before
upright rotation and UserUnit physical conversion. Analysis, editor/planner input,
original-space selection validation and final drawing use that same geometry.
Empty intersections fail; out-of-media declared crop bounds never become a
larger normalized source or a stretched selected rendering.

Output uses integer dots, origin top-left. Round physical placement once with a documented policy; report error in dots/physical units. Distinguish stock extent from printable extent and nonprintable regions. Scaling is uniform unless the user explicitly selects a separately supported nonuniform mode; version one does not offer that mode.

## Core records

- `PrinterCapabilities`: protocol, model identity, actual resolution, printable bounds, known supported ranges/enums, field/buffer limits, status support and evidence references. Each optional capability is `supported`, `unsupported` or `unknown` with provenance.
- `InstalledHardware`: confirmed accessories, thermal-transfer hardware and available media sensors. Model capability does not prove an accessory is present.
- `DeviceConnection`: stable product identity, adapter type and a validated endpoint. Credentials are secret references, never a URL printed in logs. Unknown duplicate identities require user resolution.
- `MediaProfile`: stock dimensions, tracking mode, printable region/masks, gap/mark properties, offsets, thermal method and tested speed/darkness defaults.
- `WorkflowProfile`: immutable ID/revision, input geometry expectations, extraction policy, output stock reference, order, non-label-page policy and imaging defaults.
- `ResolvedJobTicket`: immutable schema version, referenced profile revisions, effective options, source/output page mapping, copies/collation owner, bounds, provenance and cancellation identity.
- `MonochromeBitmap`: width/height, top-to-bottom rows, MSB-first pixels, 1=black, 0=white, row stride `ceil(width/8)`; unused bits at row end must be zero.
- `PreparedJob`: immutable bounded output plus expected label ordering/count, source-to-output map and digest. It is not proof of device delivery.
- `DeliveryReceipt`: accepted/prepared/transmitting/transmitted/device-confirmed/uncertain/failed/cancelled state, evidence and last known progress. Byte counts are not physical label counts.

All external schemas are versioned, validated and bounded. Reject unknown major versions; migrate old supported versions with explicit tests. Do not use Swift's implicit synthesized Codable layout as an unreviewed public wire contract. A defaulted absent capability is not automatically false or zero.

Immutable publication distinguishes failure before a final name exists from a
visible but durability-unconfirmed commit. The latter carries the exact logical
identity and canonical digest, and an identical retry must repeat the required
directory barrier before returning success. Conflicting bytes never reconcile
as an identical retry.

Accepted-job acknowledgement covers the accepted-jobs directory, store root and
root's containing directory. Final `.` and `..` root aliases fail before
namespace creation. Descriptor/name bindings are checked before and after the
configured barriers. Callers provision stable existing ancestry above
that containing directory; this is not recursive privileged provisioning or an
unconditional power-loss guarantee. A detached namespace or failed barrier is
visible-but-unconfirmed publication, never absence or safe replay authority.

Delivery consumes the verified immutable prepared artifact, never unrelated
caller-provided bytes or mutable defaults. The shared physical-device lease is
derived from that artifact's ticket-bound coordination domain rather than a
caller-supplied transport alias. It is held before delivery-state mutation, and a send-attempt state is durably
published before any transport call that might be effective. Publication
uncertainty after that point never authorizes automatic replay. Transmitted
means local handoff only; device confirmation remains a separate state.

Restart discovery is descriptor-bound and bounded. Staging and invalid
artifacts are reported rather than silently accepted, removed, or treated as
missing jobs. A discovery pass is not an atomic snapshot of concurrent intake.
Each discovered job is revalidated independently; abandoned transmitting state
becomes terminal uncertainty only under the same physical-device lease used by
delivery. Recovery never replays bytes or infers device confirmation.

## Option resolution

Precedence: explicit job choice > immutable workflow defaults > configured physical-device defaults. Validate the resolved combination against capabilities and installed accessories. An explicit unsupported option is an error, not silently ignored. A 'leave printer setting unchanged' option must be explicitly named and may not be represented as a known numeric default.

Private printer-profile version 1 retains its original canonical field set and
has no configured job defaults. Version 2 adds an exact `configuredDefaults`
object with nullable `thermalMethod`, `finishing` and `printSpeedIps` fields.
Construction and decoding validate these defaults against the existing supported
control path. Unqualified darkness/tracking/media geometry remain rejected,
not enabled by the version change. Read-only installed observations remain outside
precedence. Jobs bind the full immutable profile reference and resolved controls;
later printer-default revisions do not change accepted or prepared jobs. ID/revision
store lookup discovers the validated actual schema; explicit reference lookup
still requires exact schema, revision and canonical digest. No migration or
replacement of version-1 revisions is implicit.

Version 3 adds separately qualified `feedSpeeds` and `backfeedSpeeds` capability
objects (fact plus bounded choices) and nullable feed/backfeed defaults. Unknown
and unsupported preserve distinct facts and empty choices; supported choices
need explicit evidence and intersect the implemented 2..12 ips protocol subset.
Resolution uses the same per-field precedence. Unspecified feed/backfeed values
are `notExplicitlyControlled`, never a promise that issuing a legacy `^PRp`
preserves secondary device settings. Their version3 ticket modes are exact and
nullable only in that explicit state. Full ticket decoding re-resolves captured
controls against bound queue/profile defaults and rejects dropping both effective
secondary values. Selecting either motor speed
requires a complete resolved print/feed/backfeed tuple; the encoder never fills
omitted arguments with protocol defaults. Reference GC420d feed/backfeed facts
remain unknown and cannot be requested silently. No read-only observation enters
precedence. Other previously unqualified controls remain unavailable in version3.

Version4 adds required nullable configured default `darkness`; its supported
capability must have explicit evidence and explicit integer values are0..30.
Earlier profile formats retain exact keys and reject explicit darkness.
Queue3 adds required nullable darkness defaults and may bind profile4; earlier
queues reject the new field/reference. Ticket4 admits these references and
resolved darkness, while ticket2/3 reject downgrade attempts. The ordinary
encoder neutralizes additive relative adjustment with `^MD0` before `~SDnn`
when absolute darkness is explicit. Unspecified darkness emits neither command.
Immutable precedence, original source rendering, full decoder default binding,
output bounds and mixed-control job rejection remain mandatory. This is supplied
profile qualification, not an observed current setting or physical state-isolation
pass. The reference profile remains unchanged.

Virtual queue version 2 and resolved ticket version 3 persist these choices with
exact field sets. Older versions keep their canonical bytes and reject new
fields. No queue version 1 binds a version 3 printer profile; an explicit new
revision/format is required. The preliminary immutable-reference reader and
full decoder agree on supported queue versions, then full validation against
actual immutable profiles is still mandatory. New qualified choices reach the
inert encoder via the same queue defaults used at ticket acceptance; differences
fail before delivery. The source qualification is a profile declaration, not
hardware evidence or privileged authorization. No automatic migration or
physical-control qualification follows from a version change.

Private printer-profile7 adds required `thermalMedia` with exact method and
ribbon-presence observation records, and required direct-thermal capability fact.
Earlier schemas retain their original keys and reject the new declarations.
A configured thermal method requires independently evidenced model support and
matching installation-reported consumables. Observed ribbon is a strict JSON
boolean; absent observation is not false. Generic immutable profile references
admit7 for storage, while queue1..5/ticket2..6 retain their own printer-role bounds. Queue6 adds
nullable typed thermal defaults for configured inheritance and admits profile7.
Ticket7 binds these references and effective method; full decoding re-resolves
immutable defaults and rejects forged or dropped controls. Profile7 requires an
explicit method from job/workflow/configured layers, not legacy substitution.
Ordinary encoding reissues ^MTD/^MTT per label only for validated profile7 controls;
legacy bytes remain exact. Prepared/delivery snapshots preserve declared thermal
consumables. This is supplied qualification, not physical state-isolation proof.
Utility save/reopen preserves these declarations; it does not modify live state.

PPD/IPP option strings map to typed internal values through a fixed table. Profile display names and job titles never become ZPL syntax. Selectors are IDs, not file paths. Regeneration of PPDs/defaults is transactional and preserves unrelated queues.

## Copies, ranges and ordering

A single owner per transformation is established from M1 evidence. Do not multiply CUPS-expanded copies by a second `^PQ` count. Reject incompatible copy metadata rather than guessing.

Example source plan: page 1 gives labels A,B; page 2 gives C. Two collated copies mean A,B,C,A,B,C. Uncollated copies mean A,A,B,B,C,C. A source page-range 2 means C before copy expansion. Provide separate source-page and output-label counts. Browser sheets that already duplicate content are still content; do not invent de-duplication.

## ZPL encoder

Encode each physical label in a complete, well-delimited format. Emit validated positioning and graphic bands without exceeding documented `^GF` field limits or narrower profile limits. ASCII hex counts refer to decoded bytes. Band boundaries and blank trailing rows must be correct; do not split one label into multiple label formats. A test decoder/independent oracle reconstructs the exact packed bitmap. [R07](REFERENCES.md#r07)

Start uncompressed; add documented lossless encodings with fixed vectors and fallback. Do not assume a command's compression selector and a textual compression convention are interchangeable. Check payload length, checksums when applicable, field offsets, first/last band and widths not divisible by eight. Never persist/download fonts or graphics to device storage merely to print a raster label.

## Initial engineering limits (tunable with evidence)

| Resource | Initial proposed cap |
|---|---|
| Input document | 100 MiB |
| Source pages | 1,000 |
| Planned output labels including copies | 10,000 |
| Width/height | 8,192 / 65,535 dots, also limited by model |
| Pixels per rendered label | 32 Mi pixels |
| Prepared temporary job output | 512 MiB |
| In-flight rendering | One page by default; bounded concurrency only after benchmarks |
| Untrusted status frame | 64 KiB |
| Render deadline | 60 seconds per page; enforce using an isolated worker if a native call is not cancellable |

Limits are explicit project choices, not Zebra specifications. Check multiplication/addition overflow before allocation. Reject before physical output where possible. A timeout kills only the owned unprivileged worker and produces a clear error. Do not override CUPS sandboxing to install a resource-limit mechanism.

## Errors and privacy

Use stable error codes plus useful user messages. Examples: INPUT_UNSUPPORTED, INPUT_ENCRYPTED, LIMIT_EXCEEDED, GEOMETRY_INVALID, PROFILE_MISMATCH, OPTION_UNSUPPORTED, ACCESSORY_UNKNOWN, TRANSPORT_FAILED, DELIVERY_UNCERTAIN, INSTALL_PERMISSION_DENIED. Do not report all failures as 'printer offline'.

Normal diagnostics contain no document title, bitmap, barcode contents, user home path, serial or private endpoint. Debug payload export is opt-in, local, reviewed and TTL-limited. Production status does not depend on preserving label contents indefinitely.

## Reference-target and release-mode additions

For GC420d, retain `advertisedNominalDPI=203` separately from documented physical pitch `8 dots/mm`. The nearest-dot nominal 4×6 face oracle is 813×1219, 102 bytes/row, 124338 packed bytes and 3 white row-padding bits. This is not a measured printable region; liner/gap/offset fields remain unknown until observed. See [reference](hardware/GC420D.md).

`BuildSigningMode` is explicitly `localAdhoc`, optional `localCertificate`, or future `developerID`; it must not silently switch modes after failure. An artifact report distinguishes payload signature, installer-container signature, OS launch assessment, authorization and provenance. Missing Team ID is expected for `localAdhoc`, not a cue to trust every same-bundle-ID client. Actual installed-code trust must follow [local-signing boundaries](LOCAL-SIGNING.md).

Hardware qualification and release scope are separate fields. `notApplicableToInstalledBaseline` does not mutate the generic device capability to unsupported or close its broader physical tests. Future production schemas must preserve that distinction; `docs/reference-target.json` is planning data, not the production wire schema.


## Qualified physical geometry persistence

Profile5 adds exact physicalGeometry capability objects for width, continuousLength,
homeX and homeY, each fact plus nullable maximumDots. Supported values require
explicit evidence and the bounded implemented subset; unknown/unsupported require
nil limits. Nullable tracking and mediaGeometry defaults are required fields.
The latter has exact nullable widthDots/lengthDots/originXDot/originYDot fields.
Profile1..4 canonical keys and behavior remain unchanged; no automatic migration.
Queue4 adds the same required nullable defaults and can bind profile5; older queues
reject new fields/reference. Ticket5 binds those exact versions. Profile-reference
versions are not interchangeable with queue/workflow versions in reference slots.

Resolution is per physical field, job over workflow over configured profile.
Complete effective home and explicit qualified continuous mode/length are required.
Conflicting sensed mode/retained configured length fails, not silent field discard.
Gap mapping is explicit and qualified; black-mark offsets and sensed-stock length
remain unavailable. Ordinary output places width/home/tracking before first ^FS
and original packed graphics. Both direct and prepared bitmap encoding check the
same necessary known extent/home containment, using guarded subtraction. Unknown
shift/top/current state and stock-versus-printable extent are not invented values
or physical validation. Complete jobs reject mixed geometry on one profile revision.

## Qualified offsets in immutable jobs

Private profile6/queue5/ticket6 extend the preceding exact formats with nullable
`offsets` defaults and setting values. The exact three fields are
`blackMarkOffsetDots`, `shiftLeftDots` and `labelTopDots`; each resolves independently
at job, workflow, configured-profile precedence. Profile capabilities carry exact
`blackMark`, `shiftLeft`, `labelTop` declarations with independently evidenced
`fact` and nullable `minimumDots`/`maximumDots`. Unknown/unsupported intervals have
both endpoints absent; supported intervals require both bounded endpoints.
Black-mark mode requires a qualified explicit offset, including explicit zero.
Other modes cannot retain mark offsets; sensed modes cannot inherit continuous
length. Legacy versions cannot bind these controls or new reference versions.
Both prepared and direct encoders check known signed home/shift/top placement
against controlled dimensions before original graphics. Overflow, negative known
origin and far-edge clipping fail. Unknown device state remains unknown, and this
necessary packed-raster check is not evidence of physical printable bounds.

### Storage-only finishing declarations (printer profile8)

Profile8 retains profile7 controls and adds a required nullable finishing
configuration. Non-null records bind exact media, enabled mode/model facts,
installation declarations, per-mode stock suitability and independently qualified
cut schedules with finite batch limits. Model facts must agree with the enclosing
profile; cutter/peeler declarations cannot override its installed inventory.
Unknown and absent values remain distinct. The private canonical codec retains
its32KiB cap, fixed nested fields, bounded source IDs, sorted unique enabled modes
and actual JSON booleans. This is supplied installation evidence, not sensing.

Profile8 is currently storage-only. Queue6/ticket7 roles remain bounded to profile7;
a shared ordinary-version constraint also rejects profile8 direct control
resolution/encoding, including bitmap encoding and profile preparation. Persistence
success does not enable mechanical actions or establish physical cut/file-boundary
semantics. Finishing job/schema/normalization/delivery integration remains required
before removing this gate.

### Offline finishing control resolution

`PrinterProfile.resolveFinishingControls` requires a schema8 stored configuration
that reproduces the entire supplied FinishingJobPlan, including unselected policy
facts. Effective finishing precedence must match the plan's mode. Normal controls
share ordinary precedence and validation; returned controls retain actual schema8
and revision. This is offline resolution only: ordinary encoders still reject8,
and no mode fragment implements cut/file boundaries or peel status handling.

FinishingRasterPreparation resolves and retains those effective controls before
worker admission, beside its exact profile-bound plan, original-source provenance
and packed inputs. Revalidation against the retained profile rejects changed
effective controls; qualified geometry containment includes known home/shift/top
combinations. Unknown device geometry and physical stock fit remain unproven.

### Bound finishing normal-control prefix

ZPLControlEncoder.prepareFinishingNormalization returns a sealed profile/plan/
effective-controls/bytes context using shared ordinary normal encoding. Preparation
retains that context before rendering. Schema8 thermal commands remain explicit.
The normal prefix excludes all finishing, format, graphic, quantity and cut-trigger
commands; output policy must own these separately. Ordinary schema8 admission is
unchanged and a prefix cannot substitute for a complete accepted job payload.

### In-memory finishing output steps

FinishingOutputQualification requires additional complete-profile-bound model/status/
adapter facts. Framed candidates keep each quantity1 format, correlated printed-label
requirement, separate delayed-cut file/readiness/completion and peel-removal requirements
in explicit order. They expose no concatenated payload or delivery authority. A future
sender must independently validate its actual file/status implementation and retain the
physical-device coordination lease through required waits. Unknown status is never
completion. Ordinary schema8 queue/ticket/encoder admission remains unchanged.

FinishingDeliveryTracker is in-memory accounting only. A complete file advances to its
status requirement, never directly to printed completion. Any attempted file makes
subsequent failure uncertain, even with zero known accepted bytes. Unknown/unsatisfied
status cannot advance, and exact step/payload binding precedes attempts. Callers must
provide actual qualified correlation and hold physical ownership through all waits;
this tracker supplies neither hardware receipts nor accepted device-write authority.

InertFinishingDelivery only discards bytes and supplies synthetic status. It owns the
validated kernel lease through every file and wait, with bounded cooperative deadline/
cancellation and scope-exit release. Caller-provided coordination is simulator input;
production must derive identity from an accepted immutable ticket and verify actual
file/status behavior. Its synthetic confirmed result is never hardware evidence.

FinishingFramedArtifact is a bounded version1 archive of exact preparation context and
separately tagged ordered files/status requirements. Reopen requires independently supplied
immutable context and canonical byte equality; external lengths/counts never authorize
allocation. Archives do not manufacture accepted tickets, hardware receipts or replay
authority. Private immutable publication and durable recovery remain separate work.

FinishingArtifactStore publishes at most four private immutable96MiB binary archives
using the shared directory publication lock/durability and no-overwrite rules. The helper
counts its explicit closed record format; existing JSON publishers keep their defaults.
Uncertain publication exposes the exact selector for explicit readback. Cold reopen
requires exact reference and independently bound context; storage creates no accepted
device/ticket, status receipt or automatic post-crash replay authority.

### Conservative finishing attempt intent

FinishingAttemptStore publishes at most four immutable binary intent records, each bounded
by 1024 bytes and tied to an exact FinishingArtifactReference. Both publication and recovery
independently revalidate the archived complete output context. A recorded intent means
uncertainAfterRecordedIntent even with zero accepted bytes or synthetic completion. Missing
intent is only noRecordedIntent, never proof of no external transmission or retry authority.
Corrupt/unsafe/unreadable records fail closed. Idempotent publication does not grant another
send. Uncertain commit or cancellation after publication stops the caller; there is no reset.

### Inert persisted finishing coordination

InertPersistedFinishingDelivery composes that intent with the discard-only coordinator.
It checks and publishes intent under the existing device lease before the first discard
callback. A separate domain-prefixed artifact lease serializes the same immutable reference
across simulator aliases. Both leases are nonblocking and scoped through all file/status
steps; exceptions release ownership without clearing intent. Existing intent rejects another
run. Synthetic completion never clears or upgrades the durable observation to printed.
Accepted ticket/device binding, correlated hardware status, authoritative durable completion
and installed scheduler retry semantics remain separate acceptance gates.

### Offline finishing queue policy

FinishingQueueDefinition is a separate typed offline namespace, not an installed ordinary
queue or accepted ticket. It binds complete workflow2/profile8 snapshots, immutable
reference shapes, reported nominal stock matching workflow output, validated defaults
and one whole mode/schedule selection. Later resolution requires exact snapshots,
valid expanded counts and consistent explicit job choices. Whole selection overrides
remove obsolete cut schedules; other controls preserve shared precedence and explicit
zero. A future store must independently verify canonical reference digests. This type
provides no source/order/pitch/device admission, persistence or delivery authority.

FinishingQueueJSON uses a distinct offlineFinishingQueue kind/schema1 and16KiB cap.
Exact field sets, typed integers/booleans and full shared defaults are reconstructed
through the offline definition against supplied snapshots. Decode requires exact canonical
re-encoding bytes, preventing duplicate-key or alternate-encoding identity normalization.
Reference extraction is preliminary only; independent store resolution and digest checks
are still mandatory. The codec grants no accepted-job or scheduler authority.

FinishingQueueStore publishes bounded16KiB/256-record immutable offline policies in
finishing-queues with a separate FinishingQueueReference. Save requires independent exact
printer/workflow digest resolution, qualified workflow and complete snapshot revalidation.
Load verifies full record digest before resolving references and canonical reconstruction.
Conflicts do not overwrite; uncertain publication carries the exact typed recovery reference.
Storage or recovery does not create installed queues, accepted tickets or replay authority.

FinishingDeviceGeometry separately retains rehashed schema8 printer bytes, coordination
domain and explicit evidenced native pitch. Unknown facts fail; GC420d requires8dots/mm
on both axes. Canvas construction binds exact queue reference/domain, complete profile/
workflow snapshots and reported stock, using native pitch and existing bounds. Canvas
revalidation requires full equality. Documentary/reported declarations do not prove a
discovered unit, physical qualification, scheduler acceptance or transmission authority.

AcceptedFinishingJob accepts only original PDF bytes through verified private queue/profile
references and an explicit geometry snapshot. Worker-observed pages feed extraction; all
source pages are checked even when an explicit range excludes them. Both extraction entry
points filter ranges before copy expansion and retain selected non-label accounting. The
immutable value owns original bytes/hash, complete expanded plan, copy/range ownership and
resolved controls. Preparation cannot replace those values and verifies its result. Intake
is offlineCLI; durable acceptance, installed scheduler admission, active queue generation,
identified unit correspondence and device delivery authority remain separate contracts.

AcceptedFinishingJobStore stores canonical manifest and exact source in one immutable binary
transaction, bounded16MiB metadata/100MiB source and four records. Reopen verifies archive
digest/lengths/canonical structure, reconstructs original acceptance from exact references
and compares complete extraction/profile/queue/canvas/normalization/cut context. Changing
interpretation fails; conflicts never overwrite. Uncertain publication carries an exact
recovery reference. Recovery grants no delivery, completion or replay authority.

PreparedAcceptedFinishingJob is constructed only by the durable store factory. It reopens
and revalidates the accepted reference, renders solely retained source/plan/controls, and
carries exact accepted identity into subsequent stages. One aggregate finite budget and
cancellation span reopen/render. It grants no device delivery or replay authority.

AcceptedFinishingFramedJob retains durable accepted identity alongside complete packed
preparation and qualified ordered output. AcceptedFinishingAttemptStore verifies the exact
accepted record and full supplied context before publication/recovery. Its immutable bounded
intent is keyed by acceptance ID, independent of artifact identifiers. Recorded intent always
recovers uncertain, even after synthetic success. No clear/reset/completion/replay authority
exists. A coordinator must hold a job lease across missing-intent check, publication and all
actual delivery/status waits; idempotent storage publication is not a new sending permission.

InertAcceptedFinishingDelivery derives its simulator device domain from sealed accepted
geometry, holds an acceptance-ID lease across validation, device coordination and all waits,
and publishes conservative intent before the first discard callback. Recorded uncertainty
vetoes later admission. A single finite aggregate deadline spans validation/publication/steps.
Synthetic confirmations do not clear intent or prove hardware completion.

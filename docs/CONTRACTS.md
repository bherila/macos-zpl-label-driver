# Shared contracts and invariants

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

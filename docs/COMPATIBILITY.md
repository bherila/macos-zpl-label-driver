# Compatibility matrix

**No installed new-driver or physical-printer configuration is qualified.** Automated
rendering, storage, simulation and signature results below have their own narrow scope.
They do not establish system-dialog printing, administrator installation, USB output,
retail Mac policy or accessory behavior. States follow the M6 compatibility contract:
planned, implemented-unverified, qualified, known-limited and unsupported.

## Runtime and architecture

| Configuration | State | Evidence and limits |
|---|---|---|
| macOS 26.0 minimum / Apple Silicon | Implemented-unverified | Deployment metadata and local signatures checked; exact minimum-runtime retail installation/printing NOT RUN. |
| Hosted macOS 26.6.2 build 25G83 / ARM | Implemented-unverified | [Run35237535380](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35237535380) passed at source51d9e2a. The logged runtime is 26.6.2, not every 26.x patch. Native tests and secret-free build/signature smoke do not qualify installed or physical printing. |
| Local macOS 27.0 build 26A428 / arm64 | Implemented-unverified | Host version/build/architecture read back on 2026-09-17. Full finite gate at implementation42a4cae passed103Python/272Core/324Mac debug/release plus oracle/inert pipeline/signature/packaged-worker checks; [persisted finishing evidence](validation/M3-INERT-PERSISTED-FINISHING-2026-09-17.md). No retail-install/system-print/USB claim. |
| Local setup utility GUI on macOS 27.0 | Known-limited | Maintainer reported issue80 Part A passed using the corrected local editor. This narrow report does not qualify keyboard/VoiceOver, every workflow, newer unpublished utility changes or installed printing; [editor evidence](validation/M5-EDITOR-LAYOUT-2026-09-17.md). |
| macOS older than 26 | Unsupported | Outside the confirmed scope; no compatibility matrix or requirement to obtain an older Mac. |
| Intel | Planned | Optional independent target; no runtime, installation or physical qualification. ARM success cannot qualify Intel. |

The newer published attempt-store checkpoint385a545 has its own hosted run35238690886
pending. Prior hosted success does not qualify that head or the locally committed
persisted coordinator. Frozen Part B is a separate candidate and remains NOT RUN;
see [single-job admission](validation/M1-SINGLE-JOB-ADMISSION.md).

## Printer and transport configurations

| Configuration | State | Evidence and limits |
|---|---|---|
| S1 GC420d / USB / 4×6 pre-cut / direct thermal / tear-off | Implemented-unverified | Typed model constraints and offline rendering implemented. Model-documented pitch is8dots/mm; unit firmware, identity, sensing, current settings and observed delivery remain unrecorded. No project H evidence. |
| Cutter on the reference installation | Unsupported | Confirmed absent; forged requests must fail. This does not remove retained S2 cutter implementation/qualification requirements. |
| Peeler on the reference installation | Unsupported for the selected workflow | Tear-off only; physical peeler inventory is unobserved and no peel support is inferred. |
| Gap/web sensing, home/shift/top offsets, current settings | Planned unit observation | Qualified generic controls exist; pre-cut stock alone establishes no unit sensing or offsets. No automatic calibration or persistent save. |
| Raw TCP / other models or transports | Implemented-unverified | Inert/loopback delivery work is separate from USB. No matching physical configuration is qualified or substituted for S1. |
| S2 cutter/peeler/rewind/thermal-transfer configurations | Implemented-unverified | Profile/control/framing/storage/simulator work retains independent model/accessory/stock facts. No installed accessory behavior or ribbon configuration is physically qualified. Ordinary profile8 admission remains gated. |
| IPP / AirPrint | Planned optional investigation | No compliance or shipping-adapter claim. No server is inferred from the interface boundary. |

Application input media and physical stock remain distinct. Native-size and Letter/A4
extraction inputs all require their own exact profile/layout and physical-output evidence.
A source-document preview, analytic fixture or successful generic ZPL round trip does not
qualify any printer model, firmware, stock, finishing accessory or status protocol.

## Application and workflow matrix

| Application / path | State | Required evidence still open |
|---|---|---|
| Preview native-size and Letter/A4 extraction | Planned | Exact app/OS version, immutable workflow/profile/layout revisions, system dialog, original PDF fidelity and authorized physical output. |
| Safari native-size and Letter/A4 extraction | Planned | Exact app/OS version and separately observed browser/system printing for each declared layout. |
| Chrome native-size and Letter/A4 extraction | Planned | Exact app/OS version and separately observed browser/system printing for each declared layout. |
| Firefox native-size and Letter/A4 extraction | Planned | Exact app/OS version and separately observed browser/system printing for each declared layout. |
| Offline native setup/editor and original-source worker | Known-limited | Automated worker/packed-preview tests and narrow reported Part A GUI evidence; full GUI/accessibility and installed workflows remain open. |

No claim covers every carrier site or every Zebra printer. Each shipping layout needs a
cleared synthetic sample, exact revision and reviewed extraction behavior; unexpected pages
cannot silently disappear.

## Distribution and lifecycle

| Delivery mode | State | Evidence and limits |
|---|---|---|
| Local ad-hoc build/signature | Implemented-unverified | Secret-free nested-signature, ARM/minimum-runtime metadata and packaged-worker equality checks passed. Signatures establish no publisher trust, Gatekeeper policy or installed helper identity. |
| Account-free installation/update/rollback/uninstall | Planned qualification | Active S1 target. Privileged authorization, exact helper/backend identity, restart repair and clean retail-host lifecycle remain open. |
| Developer ID / notarized downloads | Planned deferred S3 | Optional future mode; not an active Apple-account/credential blocker and not passed by ad-hoc signatures. |

## Promoting a row

Record the exact app/OS/build/architecture, model/resolution/firmware, connection,
stock/sensing/accessories, settings/profile/layout revisions, source SHA, prescribed evidence
level and observed result. Missing firmware, unit identity or runtime evidence stays unknown.
Qualify only the tested combination. A checked declaration or reference digest is not an
independent semantic/hardware review; [traceability](TRACEABILITY.md) currently has an empty
per-ID evidence ledger and correctly reports no complete mandatory qualification.

Preserve the existing raw-print queue: its reported success is a comparison baseline,
not evidence for this project's filter/renderer/backend or shared coordination. See the
[hardware reference](hardware/GC420D.md), [release scopes](RELEASE-SCOPES.md) and
[scope status](SCOPE-STATUS.json). S1 results cannot close S2 accessory gates or deferred S3.
No merge, binary publication or physical-test permission follows from this matrix.

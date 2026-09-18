# Ordinary control coverage audit — 2026-09-17

Source inspected: published df657e9 on PR #81. This is source coverage,
not printer qualification. M3-AC03 remains unchecked. The bounded status decoder
and experimental compression do not close the full system control requirement.

## Actual current boundary

`PrinterControlRequest`, `PrinterControlDefaults` and
`ResolvedPrinterControls` live in LabelCore. `PrinterProfile.validate` rejects
unqualified explicit requests before rendering. `ZPLPreparedLabelEncoder` uses
`ZPLControlEncoder` inside the prepared immutable label envelope. It is not
wired to a selected production scheduler/backend. ADR 0003 still gates that
selection on actual M1 admission and lifetime evidence.

| Required control | Current source behavior | Remaining implementation |
|---|---|---|
| Print speed | Typed choices; reference 2/3/4 ips; exact `^PRp` output | Qualified system-dialog/default propagation and physical isolation |
| Feed/backfeed speeds | No request/default/capability fields | Typed independent model ranges, optional argument semantics, snapshot/codec propagation and cited mapping |
| Darkness | Typed request/default; every explicit request fails validation; encoder rejects it | Qualified model range and semantics, explicit command mapping distinct from image threshold |
| Direct thermal | Resolved as direct thermal; no thermal command emitted | Cited explicit ordinary mapping and supported state isolation policy |
| Thermal transfer | Reference validation and encoder reject | Separate qualified transfer model; never enable on GC420d |
| Tracking | Typed gap/mark/continuous choices; explicit requests fail | Cited command mapping, installed-media validation, unknown defaults preserved |
| Stock width/length | Typed geometry request; reference rejects | Independently qualified physical geometry, encoder mapping and bounds; no PDF/nominal-face inference |
| Origin/offsets | Geometry has X/Y origin; explicit geometry fails | Signed range and interaction policy; distinguish label home from shift/top/tear-off adjustments |
| Tear-off | Selected baseline emits `^MMT` | Finite observed physical/state isolation qualification |
| Peel/cut/rewind | Reference rejects; no command mapping | Accessory/model evidence and separate per-label/batch/end-job semantics; no mechanical command on baseline |

The two-entry `ZPLControlProtocol.gc420dBaseline` table only documents speed and
tear-off. `ZPLControlEncoderTests` checks those exact bytes, unsupported widening,
output limits and absence of persistent/geometry/copy commands. These tests
prove the conservative subset; they cannot prove omitted controls implemented.
Nominal 813x1219 output dimensions are image geometry, not permission to alter
printer width, length, sensing or origin.

## Next independent slice

Extend the offline typed protocol representation and its validation tests for
missing ordinary controls using public Zebra primary sources. Document ranges,
lifetimes and interactions before producing bytes. Preserve separate command
qualification versus read-only observed settings and installed accessories.
Do not widen production reference-profile admission merely to exercise a new
encoder. Public protocol support alone does not validate installed defaults or
physical output. Feed/backfeed controls must survive all request/default,
resolution, private profile, immutable snapshot and encoder boundaries together;
a one-site encoder addition is incomplete.

## External gates remain

B is one frozen discard-queue experiment, not full M1 acceptance. It may prove
admission and selected inert option propagation but cannot qualify device
commands, physical cancellation, held-profile/restart semantics or privileged
production identity. Actual USB delivery/coordinator integration follows the
accepted adapter decision. State-isolation labels and accessory behavior need
finite device-specific consent and hardware. No queues, privileges or printer
I/O were used for this audit.

# Independently qualified offset policy — 2026-09-17

Partial M3-AC02/03/11 implementation evidence. No new acceptance completion.
Current unpublished source adds a typed request and separate qualification policy
for black-mark offset, horizontal label shift and label top. Each model interval
requires its own supported evidenced fact. Unknown/unsupported intervals must be
absent; they never become a numeric zero or an accepted protocol-wide interval.

## Independent constraint

A numeric value inside a generic protocol interval can still be invalid for a
particular model. Every supplied offset must be checked against its independently
evidenced model range. Explicit zero must survive, while absent black-mark offset
must not silently select the protocol default. Black-mark mode and offset require
separate tracking and offset qualification.

R45's existing conservative subset is retained: black-mark -75…283, shift
-9999…9999 and label top -120…120 dots, with model intervals contained within those
implementation intervals. No wider model category is enabled. Five focused
`OffsetControlQualificationTests` passed exit0, covering exact lower/zero/upper
bytes, protocol-valid/model-invalid and Int extremes, each malformed declaration,
mode/offset/tracking qualification, competing tracking and finite output limits.
The full finite 900-second `bash scripts/ci-swift.sh` gate passed ownexit0: 89 Python/236 Core/290 Mac debug/release;132 original and180 ASCII independent round trips;finite benchmark/inert ABI/pipeline harnesses;ARM/minimum26 native metadata, nested ad-hoc signatures and packaged-worker PBM/ZPL equality. Local artifact: `artifacts/setup-app.m0LXed`.

Fresh official-source corroboration: [Zebra ^MN](https://docs.zebra.com/us/en/printers/software/zpl-pg/zpl-commands/%5Emn.html)
records model-category ranges and that its offset parameter applies only to mark
mode. [Zebra S4M menu table](https://cpws.zebra.com/cpws/docs/s4m/s4m_menu_details.htm)
corroborates the shift/top intervals. The latter is model-specific corroboration,
not a GC420d qualification. Existing R45 primary guide is the command provenance;
no third-party renderer/manual mirror is relied upon or committed.

## Scope and remaining work

This policy emits bounded offline fragments only. Ordinary profile/queue/ticket
persistence, default precedence, prepared-job integration and utility selectors
remain work. Ordinary reference profiles still reject black-mark controls and
cannot activate these new offsets. Signed offsets also require effective-origin
and packed-raster containment integration before production placement claims.
Unknown home/top/shift/device state is not a proved physical printable rectangle.
No reset/calibration/save/erase/firmware, printer I/O, queue/admin action or physical
label occurred. No merge or binary release. Part B's frozen bytes are unchanged.

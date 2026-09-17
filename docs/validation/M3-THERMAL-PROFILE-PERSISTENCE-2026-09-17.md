# Thermal profile persistence — 2026-09-17

Partial M3-AC02/03/11 and M5-AC04/05 implementation; no new acceptance completion.

## Independent constraint and contract

Loaded-consumable declarations must survive immutable save/reopen without
becoming model support, sensor proof or inferred absence. Private profile7 adds
an exact required `thermalMedia` object containing independently encoded method
and ribbon-presence observations, plus required `directThermal` capability fact.
Thermal-transfer support retains its existing separate capability fact.
New `ThermalMediaConfiguration` carries the observations explicitly. A configured
thermal method is checked against its own supported evidenced model fact and
matching installation-reported media/ribbon configuration before constructing
profile7. The conservative direct-thermal policy requires ribbon observed absent;
transfer requires ribbon observed present. No protocol or model default supplies
these observations. Unknown remains unknown.

Profile7 retains schema6 offset/geometry/motor/darkness qualification and defaults.
Profiles1..6 retain exact canonical fields and cannot carry the new declarations;
no automatic migration occurs. Reference GC420d remains schema1/direct-only with
unknown loaded consumables. Provenance is the existing public R45 ^MT table and
`M3-QUALIFIED-THERMAL-POLICY-2026-09-17.md`; no new physical inference.

Strict decoding requires exact new keys and valid observation evidence; observed
ribbon values must be actual booleans, never numeric0/1, strings or null. Canonical
encoding also validates observation/source evidence. Generic immutable references
admit profile7 so private storage can round-trip it. Queue1..5 and ticket2..6
remain unable to admit profile7: queue construction has an explicit printer-role
bound independent of the generic reference bound. This is a staged persistence
contract, not completed ordinary thermal-transfer job support.

Utility saves preserve thermal observations along with captured effective defaults,
model facts and old revisions. One synthetic direct-thermal save/restart case
passed with the seven existing editing-model tests (8 focused cases, own exit0).
Five initial focused Core cases passed own exit0: both methods canonical equality,
combined geometry/offset preservation, unknown state, invalid configured defaults,
strict ribbon/key/version rejection and legacy exactness. A sixth case now checks
that admitting a private profile7 reference does not widen legacy queue admission.
All6 thermal persistence Core cases passed in the full finite 900-second
`bash scripts/ci-swift.sh` gate, own exit0:89 Python/252 Core/307 Mac debug/release,
132 original and180 ASCII independent round trips per mode, finite benchmark/inert
ABI/pipeline harnesses, ARM/minimum26 product metadata, nested ad-hoc signatures
and packaged-worker PBM/ZPL equality. Local artifact: `artifacts/setup-app.WlYEAy`.
This is automated evidence, not scheduler/GUI/physical acceptance. Deliberately omitting the thermal snapshot from utility-save construction made
the new save/restart case fail own exit1. Source restored byte-for-byte (SHA256
f9d2d0b2149fa79ee1d2e40cc98f224227aca885e23eae711c08064b5ffc8531);
all8 restored editing-model cases passed own exit0.

## Remaining implementation and evidence

Queue/ticket version binding, per-job/default thermal precedence, ordinary encoder
and original-PDF preparation integration, and qualified utility thermal selection
remain the next slice. Finishing/accessory policies remain unfinished. Supplied
installation facts are declarations, not authenticated sensor observations or
proof that physical consumables have not changed since capture. Actual printer
behavior/isolation, loaded-media/ribbon checks, M1 adapter/privileged scheduler,
GUI/accessibility and physical output remain open. No printer I/O, administrator
action, merge, release or binary publication. Part B frozen candidate unchanged.

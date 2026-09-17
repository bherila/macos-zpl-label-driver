# Independently qualified thermal policy — 2026-09-17

Partial M3-AC02/03/11 implementation evidence; no acceptance completion.

The nearest independent constraint is loaded consumable compatibility: model
support for a command does not prove that compatible media and ribbon are loaded.
`ThermalControlQualification` validates the requested method against its own
supported evidenced model fact, an explicitly installation-reported matching
media method, and installation-reported ribbon presence. Thermal transfer needs
ribbon present. This conservative direct-thermal policy requires observed ribbon
absence. Unknown ribbon state is never false; model documentation cannot stand
in for an installation observation. These records are supplied facts, not an
independent authentication or sensor measurement of the physical configuration.

The existing R45 public Zebra P1134473-11EN Rev A ^MT table (printed page311)
is the command provenance: thermal-transfer media uses ribbon, direct-thermal
media is heat sensitive and requires no ribbon; T and D select the method.
No proprietary driver or third-party manual was consulted or committed.

Four focused `ThermalControlQualificationTests` passed own exit0. Both methods
produce exact bounded offline ^MTT/^MTD fragments only after the independent
checks. Tests cover mismatched media/ribbon, each unknown/unobserved/documented
installation substitute, each unavailable model fact, output cap and unchanged
GC420d thermal-transfer rejection. Full finite 900-second `bash scripts/ci-swift.sh` gate passed own exit0:
89 Python/246 Core/306 Mac debug/release, 132 original and180 ASCII independent
round trips per mode, finite benchmark/inert ABI/pipeline harnesses, native ARM
and minimum26 metadata, nested ad-hoc signatures and packaged-worker PBM/ZPL
equality. Local artifact: `artifacts/setup-app.xIU3Kd`. This is automated evidence,
not GUI/scheduler/physical acceptance. Deliberately omitting the independent
ribbon compatibility check made the combination test fail exit1 with two
assertions, one per method. Source restored byte-for-byte (SHA256
b59bfee8acb10436a5f1c47eada8569b28dbefc203c96e54aa9e243713415397);
all246 restored Core tests passed own exit0.

## Remaining integration and gates

This slice does not change ordinary profile6/queue5/ticket6 admission or encode
thermal-transfer jobs. Follow-on work must bind these facts and defaults to
immutable profile/queue/ticket revisions, preserve per-job precedence, enforce
policy before prepared output and ordinary encoding, and expose qualified native
controls. Finishing/accessory policies and production adapter remain unfinished.
Physical consumable verification, device behavior, GUI/accessibility and M1
scheduler/helper evidence remain NOT RUN. No printer I/O, administrator action,
merge, release or binary publication occurred. Part B remains frozen unchanged.

## Source checkpoint

Locally committed source62dd3c5000ac746e79c2e28c9157eb19d5c1d09a is not yet
pushed. Previous persistence sourcecacca166ce0b62df7e2ab3299a96b63e1f927c7e
remote/PR81 head confirmed equal; exact hosted run35216715041 in progress.
Preceding8b70383 run35216048756 passed. No hosted thermal-policy pass is claimed.

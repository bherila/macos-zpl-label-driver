# Immutable thermal job binding — 2026-09-17

Partial M3-AC02/03/11 and M5-AC04/05 implementation; no acceptance completion.

## Independent constraint

An immutable profile's loaded-consumable declarations must match the effective
job controls before preparation and remain observable in prepared/delivery
snapshots. Job choices override workflow defaults, which override configured
defaults. A higher-priority incompatible method fails; it does not fall back to
a compatible lower-priority setting. Profile7 requires an explicit method from
one of those layers, rather than silently substituting legacy direct thermal.
Unknown consumables cannot admit either explicit method. The existing public R45
^MT table and independently qualified thermal policy remain provenance.

Queue6 admits profile7 and makes its required thermal default nullable for
configured inheritance, or a typed direct/transfer choice. Queue1..5 retain their
exact direct-thermal defaults and reject profile7. Ticket7 admits queue6/profile7
and captures effective thermal controls under immutable references. Earlier
formats reject new references and transfer controls; downgrade/forged/drop cases
fail. Full decoding re-resolves bound defaults and checks the stored controls.
No migration of old immutable revisions is implicit.

The ordinary encoder emits explicit ^MTD/^MTT before graphics for profile7,
reissued for every label, alongside qualified motor/darkness/tracking/geometry/
offset controls. Legacy profiles retain their exact bytes. Encoder admission of
transfer remains restricted to sealed profile7 controls from validated resolution.
`JobProfileSnapshot` now includes the immutable thermal consumable declarations;
prepared payload and receipt equality cannot discard them. No hardware completion
or lasting state-isolation claim follows from producing a fragment.

## Automated evidence

All256 Core tests passed own exit0, including three new thermal integration cases
and one queue6/ticket7 case. Tests check exact method commands, both prepared/direct
encoding entry points, geometry/darkness/offset composition, inherited configuration,
higher-priority mismatches, unknown consumables, required explicit method, immutable
snapshot and strict queue/ticket thermal tampering/downgrades/future role bounds.

52 focused native pipeline/setup/editing cases passed own exit0. The new inert
original-PDF case prepares two labels under profile7/queue6/ticket7, verifies stored
controls and declared consumables, exact per-label ^MTD and existing geometry/
offset tuple, then bounded inert transmission of precisely the stored bytes.
This native case remains GC420d direct-only; synthetic transfer qualification is
portable-test-only and never assigned to the GC420d. The existing model/pitch
admission guard remains intact. Setup offset qualification now admits profile7;
the combined utility save/restart test now enumerates schemas6/7 while preserving
all motor/darkness/geometry/offset/thermal facts. Full finite 900-second
CI-equivalent `bash scripts/ci-swift.sh` gate passed own exit0:
89 Python/256 Core/308 Mac debug/release, 132 original and180 ASCII independent
round trips per mode, finite benchmark/inert ABI/pipeline harnesses, native ARM
and minimum26 metadata, nested ad-hoc signatures and packaged-worker PBM/ZPL
equality. Local artifact: `artifacts/setup-app.a6LBzU`. This is automated
evidence, not scheduler/GUI/physical acceptance. Deliberately omitting ordinary
thermal command emission made the composition test fail own exit1 with two
assertions, one per method. Encoder source restored byte-for-byte (SHA256
248a49291b656a24f77decdc756ee56e0f02d61839a3cb1309a1fef6b6fea568);
all256 restored Core tests passed own exit0.

## Remaining work and evidence

Qualified native thermal-method editing remains a following slice; no UI claims
for transfer were added. Other-model native pitch/model qualification and physical
thermal behavior require their prescribed evidence. Finishing/accessory policies,
production M1 adapter/privileged identity/lifecycle, installed queue/default/dialog
management, keyboard/VoiceOver, USB, faults and physical isolation remain open.
Supplied installation declarations do not independently authenticate loaded media
or prove it has not changed. No printer I/O, administrator action, merge, release
or binary publication. Part B frozen candidate unchanged.

## Source checkpoint

Implementation source5698f2f34ba5322af9bb86789033cd952806d204 contains this
validated slice. Publication/readback and hosted CI are separate checkpoints;
no hosted pass for this source is claimed here. Precedingbe681ca hosted
run35218292332 last observed in progress before this checkpoint.

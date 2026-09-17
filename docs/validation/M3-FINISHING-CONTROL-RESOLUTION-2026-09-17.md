# Shared offline finishing control resolution — 2026-09-17

Partial M3-AC02/03 implementation; no new printer command or ordinary admission.
PrinterProfile.resolveFinishingControls requires schema8 and stored finishing
configuration. It reconstructs the requested plan from the profile's complete
media, stock, accessory/mode and schedule policy and compares the whole plan.
A caller cannot substitute another policy merely because selected mode/count agree.
Resolved job/workflow/configured finishing precedence must match that plan's mode.

Effective control resolution is shared with ordinary jobs. Thermal/consumable
qualification, per-field geometry and signed-offset inheritance, motor tuple,
darkness and tracking combinations use the same validation. The public ordinary
validate method retains its tear-off gate and delegates every other control to
the shared validator. No fake legacy profile is created; resolved controls retain
schema8 and actual revision. Existing ordinary resolve/control/bitmap/prepared
encoder gates continue rejecting schema8. Cut boundaries remain intentions, and
no mechanical commands, copies or transport operations are emitted.

Nearest independent constraints: finishing policy cannot relax normal effective
control validation, and identical selected output must not hide a changed complete
policy. Two new focused cases exercise both: all four qualified finishing modes,
independent normal invalid darkness for each, both thermal methods and incompatible
consumables, explicit zero, job/workflow/configured per-field precedence, invalid
speed/tracking, changed batch qualification despite tear-off selection, legacy
schema rejection and ordinary encoding rejection. Six focused cases passed own0.
Initial test setup wrongly treated configured continuous tracking/length as invalid;
the fixture already supplies a valid length. The corrected negative uses black-mark
tracking without its independently required offset; acceptance was not lowered.

Removing shared non-finishing validation failed12 independent assertions ownexit1.
Removing full policy equality failed2 assertions ownexit1. Restored source SHA256
655da604915d195b56de495042a9402306ba358345680c999027e9b0a52ec0ac;
six restored focused cases passed ownexit0. Finite full gate follows; no terminal
full success claimed. Accepted queue/ticket/device binding, ordinary mechanical
encoding and qualified wire/file/cut/peel semantics remain open. No printer, admin,
GUI, merge or binary publication action. Frozen Part B unchanged.

Full finite900s gate is live under session15513; log
`/tmp/zpl-finishing-resolution-full.log`. Poll this same handle until terminal.

## Reviewed in-progress full gate

Manual source review and tracked/new-file disclosure scan passed. Restored source
hash is unchanged. The same finite session15513 passed272Core debug/release with
zero failures; native/build/signature/package stages remain live. No full pass claimed.
Hosted35226880650 for publisheda68b011 was freshly observed in progress.

## Terminal local gate

Full finite900s session15513 completed ownexit0:89Python/272Core/323Mac debug/release,132 strict and180 ASCII oracle round trips per mode, finite benchmark/inert ABI/pipeline checks, ARM/minimum26 metadata, nested local ad-hoc signatures, unavailable Developer-ID negative and packaged-worker PBM/ZPL equality. Artifact artifacts/setup-app.GmXaIw. No printer accessed.
Source/disclosure review passed; restored source hash unchanged. Ordinary/mechanical encoding, accepted queue/ticket/device and manual/hardware evidence remain open.

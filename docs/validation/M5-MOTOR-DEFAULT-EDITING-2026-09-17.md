# Offline setup motor-default editing — 2026-09-17

Additional partial M5-AC04/10 and M3-AC02/03 only. No manual GUI,
accessibility, queue installation, scheduler or physical evidence.

## Constraint and implementation

Editing one speed must retain the other effective configured defaults and
produce a tuple admitted by the ordinary encoder. The old setup model started
with an empty print selection and omitted feed/backfeed from its workflow draft.
The regression reproduced six assertion failures before the implementation.

The model initializes selections from its immutable profile. Feed and backfeed
choices are exposed separately only for supported qualified capability facts;
unknown reference capabilities remain unknown and offer no choices. Invalid
choices fail without replacing the selection. Clearing a selection falls back
to the configured profile value, with explicit wording; an absent configured
value is described as not explicitly setting the speed, not preserving the
physical device setting. Print choices retain the ordinary encoder subset.

Draft resolution uses profile precedence and ordinary encoder validation before
returning workflow defaults. A partial tuple remains editable but blocks
installation readiness and supplies an actionable validation message. Readiness
also still requires observed identity and both hardware confirmations. The
view exposes the qualified selectors and the actual readiness reason, including
incomplete combinations, rather than always blaming missing USB discovery.
No profile revision is rewritten, no queue is installed and no command is sent.

## Validation

Nine focused native tests passed, including configured-default preservation,
independent model choice sets, unknown capabilities, nil fallback and an
incomplete draft combined with an observed synthetic identity and confirmed
stock/tear-off. The subsequent full gate includes the final readiness wording.
Full `bash scripts/ci-swift.sh` passed exit0 on local macOS27 ARM, under a
900-second timeout: 89 Python / 210 Core / 278 Mac debug/release; both 132 original and 180 ASCII oracle round-trips, 12 finite benchmark CLI cases, 15 inert CUPS ABI cases, native builds, nested local-ad-hoc signatures, ARM/minimum26 and packaged PBM/ZPL equality.
Repository preflight passed; tracked/changed disclosure scan and manual diff
review found no private fixture or identity payload. New app artifact
`artifacts/setup-app.h6NMIU` is built/signature-verified, not manually tested.

## Remaining acceptance

Factory GC420d feed/backfeed qualification stays unknown. The synthetic qualified
fixture is not unit evidence. A real UI/VoiceOver/keyboard pass, installed queue
editing, system print-dialog propagation and physical default/state-isolation
checks remain NOT RUN. Part B retains its separately frozen candidate.

# Offline qualified darkness editor — 2026-09-17

Additional partial M5-AC04/10 and M3-AC02/03 only. No manual GUI,
keyboard/VoiceOver, system-dialog, installed queue or physical evidence.

## Independent constraint

Editing a draft must retain effective qualified darkness defaults alongside
independent print/feed/backfeed values. Unknown installed darkness must not
be represented as zero or manufacturer defaults. The old model resolved a
configured darkness value but dropped it from returned workflow defaults;
the old-code regression reproduced two nil-versus15 assertion failures.

## Implementation

The draft starts from the immutable profile configured default. Choices0..30
are available only for profile4 supported darkness with non-unobserved evidence,
matching the ordinary profile/encoder admission boundary. Explicit0 is distinct
from nil. Invalid values throw without replacing the last selection. Clearing
selection uses the configured fallback, or no explicit setting when absent.
Unknown, unsupported, supported/unobserved and legacy profiles expose no choices;
unsupported and unknown facts remain visually/accessibly distinct.

The view supplies a qualified absolute-darkness picker and accessible hint.
Its caption explains that explicit output replaces relative adjustment when
printing. Qualified profile range is labeled separately from unknown current
state. Draft resolution includes darkness and returns the validated effective
value with the independent motor settings. No profile revision rewrite, printer
command, queue installation or current-setting observation occurs during editing.

## Validation

Thirteen focused native setup tests passed, including configured preservation,
all31 choices/explicit0, bounds/no-clamping, nil fallback, qualification/legacy
rejection and joint qualified motor/default retention. Constructing the qualified
SwiftUI view is automated evidence, not a rendered/manual accessibility pass.
Full `bash scripts/ci-swift.sh` passed exit0 under900-second timeout on local
macOS27 ARM: 89 Python / 217 Core / 283 Mac debug/release, both132 original and180 ASCII round-trips, twelve benchmark CLI cases, fifteen inert ABI cases, native builds, nested local-ad-hoc signatures, ARM/minimum26 metadata and packaged PBM/ZPL equality.
Artifact `artifacts/setup-app.tqOIzw` is built/signature-verified, not manually
tested. Tracked/changed disclosure scan and manual diff review passed.

## Remaining acceptance

Factory GC420d darkness remains unknown and has no selector. Supplied synthetic
qualification does not establish installed unit support/current state. System
dialog and saved queue editing, keyboard/VoiceOver and physical alternating-profile
state/quality checks remain NOT RUN. Frozen Part B remains unchanged.

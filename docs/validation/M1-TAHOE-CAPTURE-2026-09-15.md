# M1 Tahoe discard-queue preflight — 2026-09-15

- Exact source SHA: `ac0fdfea7964ffc322ff002d3842cd69f93db258`
- Acceptance IDs: M1-AC01 through M1-AC13 (preflight only)
- Evidence level: I (host/pre-installation), C (candidate descriptors)
- Status: BLOCKED for installed scheduler evidence
- Environment: macOS 26.6.2, arm64, Xcode 26.6, macOS SDK 26.5, Swift 6.3.3

## Observations

The host scheduler was running. The supplied `labelprobe` release executable
built as arm64, ad-hoc signed, and passed strict signature verification. Its
dependency inspection showed only system frameworks and the system Swift runtime.
The three experimental PPDs passed `cupstestppd -v` after their full-bleed media
names were corrected. No queue was created, no existing queue was modified, and
no printer or device transport was accessed.

The standard CUPS backend directory is root-owned and a non-interactive
administrator authorization check was denied. Consequently the probe was not
installed, the discard queue was not created, and no scheduler, document-fidelity,
option, restart, cancellation, or helper-admission acceptance criterion is passed.

## Next action

Use the local supported authorization flow to install only a root-owned,
world-readable/executable `labelprobe` backend and a non-default, unshared queue
named `LabelProbe_DISCARDS_JOBS` with destination `labelprobe://discard`. Preserve
the existing default and all unrelated queues. Test only synthetic fixtures, then
remove the exact owned backend and queue according to the recorded rollback plan.

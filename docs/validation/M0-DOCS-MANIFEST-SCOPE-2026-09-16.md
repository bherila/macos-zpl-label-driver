# M0 documentation/manifest CI scope — 2026-09-16

At `431f0d6b096f0beb3251539dd46e8440061115f2`, the classifier permits
the mandatory repository manifest alongside recognized documentation only.
A manifest-only diff remains uncertain and launches native tests; adding code,
workflow, or unknown paths also launches them. Empty/unavailable diffs continue
to fail open to testing, not to a false green.

The observed PR #40 run `35070491708` launched native compilation because its
documentation change also updated `MANIFEST.sha256`. This is the concrete
regression being corrected, not a failure of its product tests.

Local checks on the classifier implementation passed: repository preflight,
67 Python tests, 165 LabelCore debug tests, and 152 LabelMac debug tests.
Two Python regressions cover docs plus manifest and manifest-only/substantive
changes. Native tests were run with pipe-failure propagation enabled.

This follow-up changes documentation/metadata/manifest only and targets the
classifier implementation branch. Its automatic PR run must show repository
preflight success, native macOS skipped, and `ci-required` success before the
docs-only half of M0-AC06 is recorded as observed. That result is pending.
The deliberate-failure half and contributor-fork evidence remain separate.
No installation, scheduler job, printer I/O, or release occurred.

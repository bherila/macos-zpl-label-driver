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
docs-only half of M0-AC06 is recorded as observed.

Automatic PR #42 run [35070738539](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35070738539)
passed exact head `83aec6747df9518d5c38107a8d5b3b31784447d1`:
repository preflight passed, native macOS was skipped, and `ci-required`
passed. The hosted log confirms `swift_changed=false` and aggregate inputs
`SWIFT_NEEDED=false`, `MACOS_RESULT=skipped`. The Linux Python suite ran 67
tests with one platform-specific skip; this is not a native test result.
This establishes the docs-only half only.
The deliberate-failure half and contributor-fork evidence remain separate.
No installation, scheduler job, printer I/O, or release occurred.

The classifier's full automatic PR #41 run
[35070667206](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35070667206)
also passed exact `431f0d6b096f0beb3251539dd46e8440061115f2`. Its log confirms
67 Python tests, 165 LabelCore and 152 LabelMac tests in debug/release,
132 independent round trips, 15 backend and 10 filter ABI cases, one inert
pipeline case, and local ad-hoc command/app signatures. All three required
jobs passed. Thus both the classifier implementation and the docs-only path
have distinct exact-head hosted evidence; neither proves installed acceptance.

# M0 finite fail-closed CI probe — 2026-09-16

Draft PR #43 is an isolated M0-AC06 experiment, not product implementation.
One temporary Python test deliberately failed with an explicit marker at
`11084e3aee9b1df757f08b153ecce595f5940c91`. Its focused local test returned
exit 1. Automatic run [35071242478](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35071242478)
failed both repository preflight and `ci-required`; native macOS was skipped
because its prerequisite failed. The log confirms the intended assertion,
test exit 1, aggregate `REPOSITORY_RESULT=failure`, and aggregate exit 1.

Only the injected test was removed in
`e464491f9aec282d9489149f2ccb61a485fca2c8`. Automatic recovery run
[35071315857](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35071315857)
passed repository preflight and `ci-required`, with native macOS skipped.
The final diff against the base contains documentation/manifest only; the
log confirms `swift_changed=false` and the corresponding aggregate inputs.
Linux ran 67 Python tests with one platform-specific skip. Separate local
validation passed preflight, all 67 Python tests, 165 Core debug tests, and
152 Mac debug tests, with pipe-failure propagation for native commands.

Together with [the docs-only probe](M0-DOCS-MANIFEST-SCOPE-2026-09-16.md),
this establishes both prescribed observed outcomes of M0-AC06. It does not
establish branch protection, fork approval behavior, installed printing,
administrator authorization, or physical qualification. No queue, system
configuration, printer, release, or merge was changed. Never merge the
historical intentional-failure head.

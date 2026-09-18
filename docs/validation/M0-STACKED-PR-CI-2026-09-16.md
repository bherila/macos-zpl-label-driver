# M0 stacked-PR CI — 2026-09-16

At `79411af`, the normal CI workflow no longer restricts pull-request target
branches to `main`. Push builds remain restricted to `main`; manual dispatch,
read-only tokens, pinned actions, standard hosted runners, finite timeouts,
superseded-run cancellation, and the fail-closed aggregate are unchanged.

This fixes the observed missing automatic checks on the reviewable PR stack.
A regression checks that the pull-request trigger remains unrestricted while
the push trigger retains its `main` filter.

Local validation: repository preflight passed, 65 Python tests passed, 165
LabelCore debug tests passed, and 152 LabelMac debug tests passed. Product code
is unchanged from the independently reviewed/hosted-validated `53c6b99` head.
Automatic pull-request run [35069832168](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35069832168)
passed at exact head `aaf8425fea0a4bd5535146591db1ce4e06f63bdb` on PR #39,
whose target is the preceding implementation branch rather than `main`.
Repository preflight, macOS ARM, and `ci-required` all passed. Inspection of
the hosted log confirms 65 Python tests, 165 LabelCore and 152 LabelMac tests
in debug and release, 132 independent round trips, 15 backend ABI cases,
10 filter ABI cases, one inert pipeline case, and local ad-hoc command/app
signature verification. This was an automatic PR event, not manual dispatch.

This is partial M0-AC05/07 evidence only. No fork, deliberate failing-test,
docs-only aggregate, installed scheduler, or physical acceptance is newly
claimed. A correctness review is not requested for this configuration-only
slice; hosted CI is its execution oracle.

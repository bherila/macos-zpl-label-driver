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
Automatic stacked-PR execution remains to be observed after PR creation.

This is partial M0-AC05/07 evidence only. No fork, deliberate failing-test,
docs-only aggregate, installed scheduler, or physical acceptance is newly
claimed. A correctness review is not requested for this configuration-only
slice; hosted CI is its execution oracle.

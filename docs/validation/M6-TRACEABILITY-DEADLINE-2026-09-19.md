# M6 traceability report deadline — 2026-09-19

The traceability report now uses one monotonic deadline for the whole report. The prior implementation
applied an independent timeout to each manifest subprocess, so a valid manifest with many entries and
multiple evidence revisions could run past the report's intended 60-second bound.

`Deadline` is threaded through `build_report`, `source_is_unchanged`, `manifest_describes_tree`, and
`manifest_entries`. Each Git subprocess receives the smaller of its local ceiling and the remaining
report budget. Exhaustion fails closed: an unverified manifest cannot keep an evidence record current.

Regression coverage includes an exhausted report budget, a per-entry budget ending before the last
entry, and a source-match callback that consumes the shared deadline. Removing the loop budget check
fails the test, confirming that the regression exercises the bounded loop rather than only the cheap
preflight checks.

Validation on macOS arm64, source `37dfbfe`:

- `python3 -m unittest discover -s scripts/tests`: 108 tests, 0 failures.
- `python3 scripts/check_repo.py`: passed.
- `swift test --package-path Packages/LabelCore`: 313 tests, 0 failures.

This is portable repository evidence (A). It does not establish scheduler, administrator, GUI,
installed-application, USB, physical-printer, or release evidence. Hardware and release rows remain
`NOT RUN`.

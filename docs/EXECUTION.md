# Sequential agent execution protocol

## Per-slice loop

1. Read the current branch, handoff, progress and relevant four milestone documents. Inspect existing work before planning changes.
2. Select the next unblocked slice from the epic. State the acceptance IDs it advances and the tests that can run in this environment.
3. Implement a coherent change with regression tests. Keep transports inert unless explicitly authorized.
4. Run available validation. Record exact command, environment, SHA, exit result and artifact location. Inspect failures rather than hiding them with retries or `continue-on-error`.
5. Review the diff for resource bounds, permissions, data leaks, command injection, unsupported claims and missed platform behavior.
6. Commit/open a PR according to authorization. Update progress and handoff; then proceed to the next independent slice.

Suggested PR slices are planning units, not a fixed commit count. Split or combine only when the result remains reviewable and preserves acceptance coverage. Never implement six milestones as six enormous unreviewed commits.

## Continuing without merging every slice

PR-sized means a reviewable unit, not a requirement to open or merge 38 PRs before work can continue. The maintainer can choose one draft PR per milestone containing small green commits, or stacked PRs whose base is the preceding implementation branch. Record exact base/head SHAs and make dependencies explicit. Do not claim that unmerged dependency work is on main. A blocked merge/review does not prevent independent implementation or tests on an authorized working branch. Rebase or update dependencies normally after upstream changes; never force-push protected main.

## Evidence and progress

`docs/PROGRESS.json` has orthogonal fields for implementation, automated validation, macOS integration and hardware validation. Keep them independent. Use `not-started`, `in-progress`, `complete`, `blocked` for implementation; use `not-run`, `pass`, `fail`, `blocked`, `not-applicable` for validation. `not-applicable` needs a reason. A scaffold test does not complete M0 repository/CI acceptance, much less M1.

Every milestone has a checklist. Complete an item only with the required evidence level. Attach evidence to a PR or `docs/validation/` entry; public evidence must be sanitized. Keep raw labels in ignored local directories.

## Handling an unavailable Mac or printer

Record which acceptance items are blocked, the precise reproduction procedure, and expected evidence. Continue portable geometry, profiles, encoding, simulators, editor logic or documentation that does not assume the missing result. Do not continuously poll for hardware or tell the maintainer all work is done.

## Handling an M1 architecture failure

Preserve capture results and create an ADR comparing the original CUPS path with a PAPPL/IPP path against the same requirements. Do not reduce the requirement to 'a PDF can be sent somehow'. Full-fidelity input, per-job options, saved defaults and virtual workflows remain product requirements. Portable M2 and parts of M3/M4 can proceed while the adapter decision is unresolved.

## Parallelism

Default to one sequencing agent. Parallel contributors can work on bounded components only after shared contracts stabilize. Do not let separate agents simultaneously change job-ticket semantics, profile schemas, PPD generation and transport ownership without coordination. Use separate branches/worktrees and reconcile by tests.

## Completion report format

```text
Milestone / slice:
Branch and exact HEAD SHA:
Implemented acceptance IDs:
Tests actually run and results:
Manual/physical tests not run and reason:
API/schema/behavior changes:
Security or compatibility risks:
Artifacts/evidence:
Next unblocked slice:
Maintainer action required (if any):
```

No completion statement may imply hardware, GUI, release-signing or notarization validation that did not occur. Do not auto-merge or publish just because CI is green.

## Active baseline and signing scope

Do not reopen answered questions: MIT, macOS 26 minimum, GC420d USB/4×6/pre-cut/tear-off/no cutter and no Apple account are established. Use local ad-hoc mode and prove no-account installation feasibility during M1. Missing Developer ID or older hardware is not a blocker for the active scope. See the sprint baseline in [SPRINT-BASELINE.md](SPRINT-BASELINE.md) and [first-run plan](validation/GC420D-TAHOE-FIRST-RUN.md).

The reference target is not a physical test authorization. Continue inert work by default; record the finite action/label budget once the maintainer approves a local session. Keep S1 qualification separate from S2 broader accessory work and S3 deferred trusted-public distribution. Do not mark the entire epic done because one installed tear-off printer succeeds.

# M0 — Repository, project setup and CI

**Dependencies:** None
**Goal:** Establish a reproducible, honest starting repository and safe sequential development process.

## Repository initialization

Inspect the destination before writing. Use the authenticated GitHub account and confirm access to the `bherila` owner. Check whether the repo already exists; distinguish authentication/authorization/network failure from a confirmed missing repo. Do not execute `gh repo create` automatically after an arbitrary failed `gh repo view`. The handoff preparation lookup returned 404 and made no remote changes.

After confirming the requested public repository should be created, the intended CLI operation is:

```sh
gh auth status
gh repo view bherila/macos-zpl-label-driver --json nameWithOwner,url,isPrivate
# Only after resolving the result and confirming creation is appropriate:
git init -b main
# Copy/reconcile the handoff files into this checkout first.
git add .
git diff --cached --check
git commit -m "chore: bootstrap label printer driver project"
gh repo create bherila/macos-zpl-label-driver --public --source=. --remote=origin --push
```

These are instructions, not a script to run blindly. If the repo exists, clone and reconcile on a branch; do not initialize over or replace its history. MIT has been confirmed by the maintainer; retain its license and attribution before public push. Do not publish private samples included outside the handoff. Set repository description/topics and enable Issues only within granted permissions. Prefer PRs after the initial scaffold commit. Configure the stable `ci-required` status check once it exists; do not invent a passing check or disable protections to move faster.

## Build structure

Keep `Packages/LabelCore` portable and independent of Apple graphics/UI APIs. `Packages/LabelMac` depends on the local core and may import Core Graphics. The provided diagnostics target is inert. New executables, UI/helper targets and tests must be added to CI when introduced. Do not treat stub targets as working product components.

Use Swift 6 language mode, confirmed macOS 26.0 deployment target and Apple Silicon as the initial architecture. Use the standard macos-26 ARM runner; no older-macOS matrix is required. Record actual `swift --version`, Xcode, SDK, `sw_vers` and `uname -m`. Newer compilers do not establish runtime compatibility with the minimum deployment target.

## Repository policy and CI

Keep AGENTS.md, README, contributing/security policy, provenance, license, ignore rules, issue/PR templates, the epic and milestone documentation. Add a simple architecture-decision log and evidence templates. Public fixture records must contain synthetic/cleared inputs only.

The initial CI uses Linux ARM for cheap repository checks and macOS ARM for Swift/Core Graphics build and tests. Documentation-only PRs must not strand required checks in pending state. Superseded PR builds cancel; a failed build must block the aggregate check. Use standard runners, read-only permissions, pinned action SHAs, no secrets and short artifact retention. Compatibility runs are manual initially. Do not run installed queue/privileged/hardware tests on PR runners.

## Deliverables

A public repo or a precisely reported authorization block; reconciled scaffold; green real PR CI; documented build commands; progress/evidence records; security reporting setup state. The supplied code is a baseline to validate and extend, not permission to mark the entire milestone done without checking GitHub.

## Confirmed configuration and local build mode

Read [sprint baseline](../../SPRINT-BASELINE.md), [reference target](../../reference-target.json) and [local signing](../../LOCAL-SIGNING.md). Primary hardware is GC420d USB with 4×6 pre-cut stock, tear-off/no cutter. Documented model pitch and current unit settings have different provenance. Preserve unknown firmware/USB identity/sensing/defaults; no guessed device values.

Ad-hoc local signing is required without Apple accounts, Team IDs, provisioning updates or notarization. Run the inert diagnostic signing smoke on macOS 26; it uses no secrets or privileged/device operations. Validate actual deployment/architecture and final signature, not merely project settings. All added executable/app/helper targets must join CI. Keep public source versus future trusted-binary release scope explicit.

## Related documents

Read [acceptance](ACCEPTANCE.md), [instructions](INSTRUCTIONS.md) and [validation](VALIDATION.md). Shared [contracts](../../CONTRACTS.md), [sprint baseline](../../SPRINT-BASELINE.md), [local signing](../../LOCAL-SIGNING.md), [release scopes](../../RELEASE-SCOPES.md) and [validation policy](../../VALIDATION-PLAN.md) apply.

## Primary references

[R05](../../REFERENCES.md#r05), [R06](../../REFERENCES.md#r06), [R14](../../REFERENCES.md#r14), [R18](../../REFERENCES.md#r18), [R19](../../REFERENCES.md#r19), [R20](../../REFERENCES.md#r20), [R26](../../REFERENCES.md#r26), [R27](../../REFERENCES.md#r27), [R28](../../REFERENCES.md#r28), [R29](../../REFERENCES.md#r29), [R31](../../REFERENCES.md#r31). Documentation supports APIs/model facts, not unperformed runtime or physical tests.

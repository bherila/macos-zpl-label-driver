# Start here — Codex implementation handoff

**Target repository:** `bherila/macos-zpl-label-driver`
**Prepared:** 2026-09-15; revision 3 (implementation accelerator)
**Status:** specifications plus tested portable implementation candidates, not a working printer driver.

## What this package is

Six product milestones, preceded by a bootstrap milestone. A milestone is a workstream containing several reviewable PR-sized slices, not one commit. Each milestone directory contains `SPEC.md`, `ACCEPTANCE.md`, `INSTRUCTIONS.md`, and `VALIDATION.md`. Read all four before implementing that milestone. `EPIC.md` is suitable for a GitHub epic issue.

The supplied Swift packages now include tested bitmap packing, banded graphics, copy ordering, an offline vector CLI and an inert CUPS ABI probe, plus the prior Mac diagnostic. Original PDF/HTML fixtures and an independent decoder are included. Read [ACCELERATOR.md](docs/ACCELERATOR.md) before implementation. No usable driver, PDF renderer, installed queue or hardware transport is supplied. Do not describe offline CI as product acceptance.

## First instruction to Codex

```text
Implement the project described in this handoff in bherila/macos-zpl-label-driver.
Read docs/ACCELERATOR.md first and run its offline checks. Reuse the tested
components and synthetic fixtures without bypassing M1. Then read
AGENTS.md, EPIC.md, docs/DECISIONS.md, docs/ARCHITECTURE.md,
docs/CONTRACTS.md, docs/VALIDATION-PLAN.md and docs/EXECUTION.md first.
Also read docs/SPRINT-BASELINE.md, docs/LOCAL-SIGNING.md and
docs/RELEASE-SCOPES.md. MIT and macOS 26 minimum are confirmed. The first
physical target is GC420d USB, 4x6 pre-cut stock, tear-off, no cutter. Use
local ad-hoc signing without an Apple Developer account. Do not wait for
Developer ID or implement older-macOS support. Follow the first-run plan
before any authorized hardware session.
Start with all four documents in docs/milestones/00-bootstrap/.
Preserve existing repository content if a repo already exists. Do not assume
an inaccessible repository is absent. Follow the bootstrap procedure.

Work in reviewable, tested slices. Complete M0, then investigate M1 before
committing to a production printing adapter. Continue through M2–M6 in order
where prerequisites are satisfied. When a local Mac, physical printer,
credentials, or maintainer decision is required, record the exact blocked
acceptance IDs and continue independent work; never fabricate a pass.

Keep progress and a handoff current. Do not auto-merge PRs or publish releases
without separate authorization. Never inspect proprietary third-party driver software,
PPDs, binaries, or implementation. No hardware writes, queue changes,
privileged installation, or paid CI without explicit authorization for that
operation. The project goal is full workflow usefulness, not merely a CLI.
```

## Execution order

| Order | Directory | Main outcome |
|---|---|---|
| 0 | [00-bootstrap](docs/milestones/00-bootstrap/SPEC.md) | Repo, buildable starter, policy, CI, evidence bookkeeping |
| 1 | [01-printing-integration](docs/milestones/01-printing-integration/SPEC.md) | Proven macOS input fidelity, option propagation, sandbox and adapter contract |
| 2 | [02-imaging-engine](docs/milestones/02-imaging-engine/SPEC.md) | Geometry, Quartz rendering, exact monochrome preview, bounded ZPL |
| 3 | [03-printer-controls](docs/milestones/03-printer-controls/SPEC.md) | Capabilities, hardware controls, transport, coordination, failure states |
| 4 | [04-label-extraction](docs/milestones/04-label-extraction/SPEC.md) | Validated templates, teach-once crop, multi-label sheets, browser workflows |
| 5 | [05-product-distribution](docs/milestones/05-product-distribution/SPEC.md) | Native setup app, virtual printers, defaults, installation and releases |
| 6 | [06-compatibility-release](docs/milestones/06-compatibility-release/SPEC.md) | Compatibility evidence, fault/quality/performance qualification, release gate |

A proof-only M1 slice may use an inert capture backend; it must not pretend to be the finished encoder. M4 supplies editor components that M5 integrates into the setup application. No circular dependency requires a polished UI before the engine exists.

## Confirmed baseline and current package

[SPRINT-BASELINE.md](docs/SPRINT-BASELINE.md) and [DECISIONS.md](docs/DECISIONS.md) record the confirmed GC420d USB / 4×6 pre-cut / tear-off / no-cutter configuration, Tahoe 26.0 minimum, MIT and local ad-hoc signing. The [hardware reference](docs/hardware/GC420D.md) supplies documented model facts without claiming unit qualification.

Use this **complete revised archive instead of** revision 1 or 2 for a fresh checkout. In an already edited checkout, reconcile the diff on a branch rather than copying over changes. See [revision notes](docs/REVISIONS.md).

Actual OS patch/build, firmware, current settings, sensing and failing workflow samples remain observations for later gates, not reasons to repeat answered questions. Missing Developer ID is not a local-scope blocker. All hardware/privilege consent boundaries remain.

## What was and was not done during handoff preparation

A read-only GitHub lookup of the target repository returned 404. This may mean absent or inaccessible, not necessarily absent. No repository was created or modified, no issues were posted, no CI was run on GitHub, and no printer was accessed. See [ACCELERATOR-VALIDATION.md](docs/ACCELERATOR-VALIDATION.md) for the current checks. [HANDOFF-VALIDATION.md](docs/HANDOFF-VALIDATION.md) is the historical revision-2 report.

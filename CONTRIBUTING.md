# Contributing

Read AGENTS.md and the active milestone documents. [docs/BUILDING.md](docs/BUILDING.md) has the build, test and pre-commit commands for Linux and macOS. Submit focused PRs with requirement/acceptance IDs, tests and evidence. Describe skipped or unavailable validation explicitly.

Bug reports should identify application and version, macOS version, printer model and resolution, connection, media, workflow, observed versus expected behavior, and a synthetic reproduction. Avoid serial numbers, customer information and complete print payloads. A private label is not automatically safe merely because its PDF metadata was removed.

`MANIFEST.sha256` records a digest for every tracked file, and CI fails a pull request whose covered files no longer match it. Pay that in one command rather than by hand: run `python3 scripts/refresh_manifest.py` before committing, and `python3 scripts/refresh_manifest.py --backfill` when your change adds a file — `git add` it first, since the backfill reads the git index rather than the working tree. The refresh never removes an entry, and it leaves an unreadable file at its recorded digest rather than rewriting it, so a genuine integrity failure still fails the audit. Refreshing the manifest does not invalidate acceptance evidence; `source_is_unchanged` exempts it.

Code contributions must have compatible provenance. MIT is confirmed for new code; retain dependency licenses and notices. Do not contribute proprietary driver code or artifacts. Do not distribute fonts bundled from a developer's computer. Use synthetic vector fixtures where possible and redistributable test assets only after review.

Public support claims require the validation levels in docs/VALIDATION-PLAN.md. Hardware reports can be narrower than an entire printer model: include resolution, firmware family, transport, media and accessories. Unsupported and unknown are separate states.

Do not run untrusted PR code on a maintainer machine connected to a printer or holding signing credentials. Review code before local hardware or installation tests. Report security issues through the process in SECURITY.md rather than posting exploit details in an ordinary issue.

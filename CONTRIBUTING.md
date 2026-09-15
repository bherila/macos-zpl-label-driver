# Contributing

Read AGENTS.md and the active milestone documents. Submit focused PRs with requirement/acceptance IDs, tests and evidence. Describe skipped or unavailable validation explicitly.

Bug reports should identify application and version, macOS version, printer model and resolution, connection, media, workflow, observed versus expected behavior, and a synthetic reproduction. Avoid serial numbers, customer information and complete print payloads. A private label is not automatically safe merely because its PDF metadata was removed.

Code contributions must have compatible provenance. MIT is confirmed for new code; retain dependency licenses and notices. Do not contribute proprietary driver code or artifacts. Do not distribute fonts bundled from a developer's computer. Use synthetic vector fixtures where possible and redistributable test assets only after review.

Public support claims require the validation levels in docs/VALIDATION-PLAN.md. Hardware reports can be narrower than an entire printer model: include resolution, firmware family, transport, media and accessories. Unsupported and unknown are separate states.

Do not run untrusted PR code on a maintainer machine connected to a printer or holding signing credentials. Review code before local hardware or installation tests. Report security issues through the process in SECURITY.md rather than posting exploit details in an ordinary issue.

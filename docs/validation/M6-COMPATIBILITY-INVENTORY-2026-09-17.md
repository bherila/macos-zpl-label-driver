# Compatibility inventory refresh — 2026-09-17

Partial M6-AC02/03/04/12 documentation, not qualification. Existing compatibility
prose incorrectly said hosted workflows had never executed and assumed only a Tahoe
local host. Current local readback is macOS27.0 build26A428 arm64. The successful exact
source51d9e2a hosted run35237535380 logs macOS26.6.2 build25G83 arm64, Xcode26.6,
SDK26.5. Native automation is recorded separately from real installed/physical workflows.

COMPATIBILITY.md now separates runtime/architecture, printer/transport, application/
workflow and distribution/lifecycle rows using the prescribed planned, implemented-
unverified, known-limited and unsupported states. No installed or physical row is
qualified. Narrow maintainer-reported Part A remains distinct from automated tests;
minimum26.0, Intel, browser workflows, firmware/unit sensing, USB, accessories, retail
installation and authoritative status remain open. Frozen B remains a separate candidate.

Evidence: successful hosted log /tmp/zpl-traceability-hosted-pass.log, gh run view
35237535380, sw_vers productVersion/buildVersion and uname -m. The latest local source
slice already passed the full finite103Python/272Core/324Mac gate; this documentation
refresh introduces no executable target. python3 scripts/check_repo.py and git diff
--check passed. Manual disclosure review contains no unit identity, serial, firmware
dump, customer label or secret. No extra tests mirror this reversible prose change.

Per-ID assessments, independent semantic review and actual runtime/app/device/release
qualification remain incomplete. No administrator, printer, merge or binary publication
was performed. Documentation source checkpoint 523fa6b, committed locally; push pending.

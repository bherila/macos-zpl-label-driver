# Release scopes and non-transferable evidence

This is an explicit scope decision from the maintainer's hardware/OS/signing constraints. It does not delete the full feature target or convert blocked tests to passes.

## S1 — GC420d-local (active first qualification)

Target: native Apple Silicon, tested Tahoe 26.x runtime with a 26.0 minimum, GC420d USB, 4×6 pre-cut stock, tear-off, local ad-hoc build/install. Must include ordinary application printing, native and Letter/A4 extraction workflows, browser compatibility, supported speed/darkness/media/position controls and defaults, exact imaging, virtual queue coordination, guided lifecycle, privacy and correct uncertain-delivery handling.

The actual runtime patch/build, firmware, stock/tracking, settings, workflow revisions and source SHA must accompany the claim. Do not claim every Tahoe patch tested from one host, or future macOS major support from `minimumVersion=26.0`.

Cutter/peeler/ribbon physical tests are not applicable to this installation, but unsupported-option rejection **is** required. Network/Intel qualification and other printer models are not S1 blockers. Their generic implementation may continue, without support claims. Signing checks are local-mode checks, not deferred awaiting credentials.

## S2 — Broader feature/model parity (retained)

All mandatory product requirements still apply to devices that actually provide the features. Finish generic cutter/peeler/thermal-transfer/network implementations and tests, then gather matching hardware evidence before advertising them. S1 completion does not close M3-AC10 or M6-AC06 as globally passed. No universal model catalogue is inferred from GC420d.

## S3 — Trusted public binary distribution (deferred)

Developer ID identities, notarization/stapling and clean-host verified downloaded distribution are future opt-in release work. No credentials currently exist. Keep a future pipeline boundary and primary reference links, but do not demand notarization in active M5-AC11 or block local/source releases on S3.

## Reporting

For each acceptance criterion record implementation state, evidence level, scope and reason for any applicability decision. Use `docs/PROGRESS.json` for global milestone state and `docs/SCOPE-STATUS.json` for scope-level qualification. Evidence that passes S1 must not silently mark the global M3/M6 accessory scope complete. Documentation-only applicability is not hardware evidence.

Critical security, clipping, counts, unbounded resource use or uncontrolled replay defects cannot be waived in any scope. Experimental publication must disclose all incomplete S1 requirements and requires explicit release authorization. Full epic completion requires the active requirements plus retained S2 evidence, not merely a useful S1 prototype; S3 is optional rather than required for functional parity.

# M3 — Capabilities, controls, transport and job state

**Dependencies:** M1 accepted transport boundary; M2 prepared output for end-to-end tests
**Goal:** Control real printer behavior safely, serialize virtual queues and report delivery uncertainty honestly.

## Capabilities and configuration

Implement versioned printer capabilities, installed hardware, media, connection identity and resolved options. Keep unknown separate from unsupported. Model-specific speed/darkness/range restrictions must have a source and a validation state. A generic ZPL entry is conservative and must not expose unsupported finishing merely because another Zebra implements it.

Support the requested controls where hardware permits: print/feed/backfeed speed, darkness, thermal method, gap/mark/continuous tracking, stock width/length, origin/offsets, tear-off, peel, cutter and documented rewind options. Provide per-job controls and defaults through the accepted adapter; do not defer their semantics until the UI milestone. A protocol table records command, range, persistence, interactions, model limits and source for each option.

Distinguish printer darkness from image threshold and true model capabilities from installed accessories. Heat is not a temperature dial. Keep explicit calibration and persistent device configuration separate from ordinary jobs. Do not save device settings, erase objects or modify firmware automatically. Do not rely on previous job state: emit/resolve supported session settings deterministically or explicitly declare a 'leave unchanged' choice.

## Finishing

Define each cut policy by resulting physical behavior: each label, batch size, or end of job only when the device supports that policy. Simulated command output is not physical validation. Peel waiting for label removal is an expected state. Handle label-taken/media/ribbon/head-open status only where supported; absence of status is unknown, not a healthy printer.

## Transport and ownership

Implement the selected M1 backend/coordinator boundary. All product virtual queues and maintenance operations use one stable physical identity and ownership mechanism. Hold the lease/lock across actual delivery and any necessary readiness boundary. Protect against child exit races, process death, stale ownership, USB re-enumeration and queue aliases. Do not keep a stale PID file as the sole ownership mechanism.

Initial generic objectives are USB and raw TCP, with GC420d USB as the first physical integration. Raw TCP remains implemented/simulated work until suitable hardware exists and does not block S1 GC420d-local qualification. Preserve the existing working raw path as an explicit developer baseline only. Discovery is bounded and local; entering a printer address explicitly must work. Do not scan arbitrary networks. Connection credentials and discovery identifiers are not general log output.

A delegating USB backend must preserve documented ABI/environment/descriptors, security context, cancellation and status. Otherwise implement/test the required public OS USB transport separately. No shell interpolation of device paths, options or profile values is allowed.

## Job states and retries

Track accepted/prepared/waiting/transmitting/transmitted/device-confirmed/uncertain/failed/cancelled states. 'Sent bytes' is not 'printed labels'. Report partial or uncertain completion after disconnect/crash rather than replaying automatically. Safe retry before any bytes have been accepted by the transport may be bounded; after ambiguity require an explicit reviewed policy/user action. Map backend exit codes so the scheduler does not silently replay an uncertain job.

Transport cancellation cannot undo labels already accepted by the device. Device cancel commands may affect other jobs and need a model-specific policy and ownership. Unrelated hosts/queues are outside this local coordinator; document that limitation.

## First installed configuration

Implement the explicit GC420d/USB reference profile from [hardware reference](../../hardware/GC420D.md) and [planning input](../../reference-target.json), but define/review the production schema rather than treating planning JSON as an executable runtime profile. Thermal method is direct-only; selected operation is tear-off; cutter is absent. Peeler inventory is unobserved but peel behavior is disabled for this configuration. Reject forged cut/peel/ribbon/rewind options in the non-UI path too. Model-documented print-speed choices are 2/3/4 ips; do not offer 5+ or arbitrary continuous speed values for this profile.

Pre-cut does not prove a measured gap or particular sensing method. Leave gap/pitch/liner/origin and current speed/darkness unknown until confirmed. Preserve known-working settings for the authorized baseline, then resolve explicit defaults for deterministic workflow tests or disclose `leave unchanged`. No automatic calibration, persistent save, language switch or guessed modern status protocol.

The original raw queue remains installed but may bypass product coordination. Require no competing submissions through it during controlled tests; do not claim our lock serializes unrelated queues. USB identity/status and exact delivery completion remain experimentally verified, not inferred from the bidirectional hardware specification. Follow [first-run plan](../../validation/GC420D-TAHOE-FIRST-RUN.md).

## Related documents

Read [acceptance](ACCEPTANCE.md), [instructions](INSTRUCTIONS.md) and [validation](VALIDATION.md). Shared [contracts](../../CONTRACTS.md), [sprint baseline](../../SPRINT-BASELINE.md), [local signing](../../LOCAL-SIGNING.md), [release scopes](../../RELEASE-SCOPES.md) and [validation policy](../../VALIDATION-PLAN.md) apply.

## Primary references

[R01](../../REFERENCES.md#r01), [R07](../../REFERENCES.md#r07), [R11](../../REFERENCES.md#r11), [R12](../../REFERENCES.md#r12), [R22](../../REFERENCES.md#r22), [R23](../../REFERENCES.md#r23), [R24](../../REFERENCES.md#r24), [R26](../../REFERENCES.md#r26), [R27](../../REFERENCES.md#r27). Documentation supports APIs/model facts, not unperformed runtime or physical tests.

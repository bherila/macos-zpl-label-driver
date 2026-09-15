# M2 — Geometry, imaging and ZPL engine

**Dependencies:** M0; use M1 input/transform findings for production adapter integration
**Goal:** Produce deterministic, bounded label output from original documents with an exact monochrome preview.

## Validation matrix

| Case | Environment | Procedure / oracle |
|---|---|---|
| Geometry property vectors | Portable suite | Test 0/90/180/270 rotations, shifted/negative box origins, supported units, fit/actual size, non-square resolution and forbidden NaN/overflow. |
| PDF fixtures | macOS suite | Render analytic vector, transparency, raster, small text, mixed-size multipage and annotation/form cases. Compare reviewed expected behavior. |
| Encoding oracle | Portable suite | Reconstruct known images from emitted fields; force very small band limits to expose boundary errors and verify the single-label format count. |
| Failure injection | Unprivileged workers | Truncated/encrypted PDF, oversized page, disk quota, write failure, worker timeout and cancellation must produce controlled errors. |
| Scanner qualification | Authorized physical target | Print the agreed finite sample set; record scan payloads locally and publish sanitized pass counts/configuration only. |
| Benchmarks | Reference Mac release build | Measure cold/warm convert time, memory and bytes separately from transport/mechanical speed; retain baseline commit. |
| Reference pitch and band seams | Portable tests + Quartz where needed | Validate exact rational physical conversion and rounding; exercise width 813, white low-order padding bits, 321/321/321/256 rows, source placement and no extra per-band label formats. |

## Evidence and regression requirements

Record exact source SHA, toolchain/SDK/OS/app versions, observed configuration, profile/fixture IDs and hashes, expected/actual result, commands and artifact locations. NOT RUN/BLOCKED/FAIL/PASS are different. A zero exit without inspecting its expected result is not an oracle. Add a minimal regression with each corrected defect; do not update all goldens or hide errors to manufacture success.

Use the [evidence template](../../validation/EVIDENCE-TEMPLATE.md). For physical GC420d sessions use the [first-run plan](../../validation/GC420D-TAHOE-FIRST-RUN.md) and obtain a finite named-device/job/label/command allowance first. Exact observed runtime is Tahoe 26.x, not an assumed old Mac. Record local ad-hoc signature verification separately from OS policy, installed-spooler and helper authorization.

A new user account is not a clean OS host. Hosted Mac tests are not USB/physical evidence. Unsupported accessory/transfer tests remain separate from the tear-off reference setup. Publish no serials, sensitive payloads or credentials.

## Exit report

List each acceptance ID with implementation state, achieved evidence, applicable scope and open restriction. Update progress/support only to the observed level. An implemented milestone with blocked hardware or GUI evidence is not globally accepted. No Apple Developer identity is needed for the active local scope; deferred trusted-public distribution remains deferred, not passed.

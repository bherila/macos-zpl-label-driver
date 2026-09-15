# M4 — Sheet extraction and browser workflows

**Dependencies:** M2 engine; M1 workflow media behavior; M3 profile/control integration
**Goal:** Extract, rotate, scale and order labels from larger documents without sacrificing source detail or silently discarding content.

## Validation matrix

| Case | Environment | Procedure / oracle |
|---|---|---|
| Template matrix | Portable planner + macOS renderer | Use native, Letter, A4, shifted/rotated page boxes, 2-up/4-up sheets, mixed-size and clipped-region fixtures. |
| Changed-layout negatives | Automated | Move borders/anchors, alter dimensions and add competing barcode regions; inspect exact mismatch codes and no-output behavior. |
| Page-accounting sequence | Automated | Use labels A/B/C plus instruction/customs pages and explicit range/copy settings; compare plan to expected ordered IDs. |
| Editor round trip | Local Mac GUI | Define/reorder regions, switch display zoom, save, reopen and compare canonical coordinates and exact bitmap outputs. |
| Offline detection | Local Mac | Disable external network access; verify allowed local heuristic/Vision behavior and ambiguity confirmation. |
| Browser end-to-end | Local Mac + approved target | Print the same source via required browsers/system dialogs and workflow queues; record app versions, profile hashes and physical scan results. |
| Reference workflow geometry | Portable planner + Tahoe capture | Generate native/Letter/A4 synthetic sources, validate output dimensions and region bounds, then confirm actual application-facing page preservation on the selected runtime. |

## Evidence and regression requirements

Record exact source SHA, toolchain/SDK/OS/app versions, observed configuration, profile/fixture IDs and hashes, expected/actual result, commands and artifact locations. NOT RUN/BLOCKED/FAIL/PASS are different. A zero exit without inspecting its expected result is not an oracle. Add a minimal regression with each corrected defect; do not update all goldens or hide errors to manufacture success.

Use the [evidence template](../../validation/EVIDENCE-TEMPLATE.md). For physical GC420d sessions use the [first-run plan](../../validation/GC420D-TAHOE-FIRST-RUN.md) and obtain a finite named-device/job/label/command allowance first. Exact observed runtime is Tahoe 26.x, not an assumed old Mac. Record local ad-hoc signature verification separately from OS policy, installed-spooler and helper authorization.

A new user account is not a clean OS host. Hosted Mac tests are not USB/physical evidence. Unsupported accessory/transfer tests remain separate from the tear-off reference setup. Publish no serials, sensitive payloads or credentials.

## Exit report

List each acceptance ID with implementation state, achieved evidence, applicable scope and open restriction. Update progress/support only to the observed level. An implemented milestone with blocked hardware or GUI evidence is not globally accepted. No Apple Developer identity is needed for the active local scope; deferred trusted-public distribution remains deferred, not passed.

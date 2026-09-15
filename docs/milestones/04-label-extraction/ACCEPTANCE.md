# M4 — Sheet extraction and browser workflows

**Dependencies:** M2 engine; M1 workflow media behavior; M3 profile/control integration
**Goal:** Extract, rotate, scale and order labels from larger documents without sacrificing source detail or silently discarding content.

## Acceptance checklist

Evidence levels: **A** automated; **C** repository/CI/configuration inspection; **I** real macOS integration; **H** physical hardware; **R** release/distribution in the declared signing mode. See [validation policy](../../VALIDATION-PLAN.md) and [release scopes](../../RELEASE-SCOPES.md).

| Done | ID | Area | Minimum evidence | Acceptance criterion |
|---|---|---|---|---|
| [ ] | M4-AC01 | Separate media concepts | A | Input sheet and output stock remain separate through schema, editor, queue options and rendering. |
| [ ] | M4-AC02 | Extraction geometry | A | Canonical regions survive page rotation/origin/size handling and map to correct output without hidden stretching. |
| [ ] | M4-AC03 | Multiple labels/order | A | Multi-region/multipage extraction and collated/uncollated copies match the shared ordering examples exactly. |
| [ ] | M4-AC04 | Template mismatch | A | Changed size/layout/anchors and ambiguous candidates fail or hold before default delivery, with useful reasons. |
| [ ] | M4-AC05 | Non-label pages | A | Every source page is accounted for; customs/instructions are not silently dropped and explicit skips are reported. |
| [ ] | M4-AC06 | Teach-once UI | I | A user can define, reorder, preview, save, reload and correct a profile with keyboard-accessible controls. |
| [ ] | M4-AC07 | Exact source/preview | A | Detection uses only analysis inputs; final labels render from original pages and preview the actual packed output. |
| [ ] | M4-AC08 | Import safety | A | Malformed/oversized/unknown-schema profiles fail; no imported raw commands, paths or embedded private documents are accepted. |
| [ ] | M4-AC09 | Local assistance | I | Detection works offline on the minimum supported OS path or reports unavailable; new matches require confirmation. |
| [ ] | M4-AC10 | Queue workflow | I | Selecting native/Letter/A4 virtual workflows in required applications yields intended full-page capture and extraction. |
| [ ] | M4-AC11 | Physical workflow | H | Declared browser/template workflows produce correctly sized readable labels on qualified stock/device configurations. |
| [ ] | M4-AC12 | Recovery/snapshots | I | Mismatch correction, held jobs and profile edits preserve revision semantics and do not auto-replay uncertain output. |
| [ ] | M4-AC13 | Three reference workflows | A | Native 4×6, Letter-to-4×6 and A4-to-4×6 plans bind the same reference stock while preserving distinct input geometry; unconfigured or mismatched extraction never silently prints a guessed crop. |

## Completion rules

Check an item only after its exact evidence is recorded. Implemented is not physically tested. Account-free local signing is the active mode; future Developer-ID notarization is not an S1 blocker. Scope-specific nonapplicability is recorded with reasons and never silently becomes a global pass. Critical security, clipping, count/order or uncontrolled-replay defects block qualification. Use the [evidence template](../../validation/EVIDENCE-TEMPLATE.md), [progress](../../PROGRESS.json) and [scope status](../../SCOPE-STATUS.json).

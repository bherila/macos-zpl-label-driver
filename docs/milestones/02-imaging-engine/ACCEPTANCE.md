# M2 — Geometry, imaging and ZPL engine

**Dependencies:** M0; use M1 input/transform findings for production adapter integration
**Goal:** Produce deterministic, bounded label output from original documents with an exact monochrome preview.

## Acceptance checklist

Evidence levels: **A** automated; **C** repository/CI/configuration inspection; **I** real macOS integration; **H** physical hardware; **R** release/distribution in the declared signing mode. See [validation policy](../../VALIDATION-PLAN.md) and [release scopes](../../RELEASE-SCOPES.md).

| Done | ID | Area | Minimum evidence | Acceptance criterion |
|---|---|---|---|---|
| [ ] | M2-AC01 | Geometry | A | All box/origin/rotation/unit/rounding vectors pass; physical transform quantization is at most one dot under the documented policy. |
| [ ] | M2-AC02 | Original-source rendering | A | Output rendering uses the original PDF or qualified input raster, never a detection/UI thumbnail. |
| [ ] | M2-AC03 | PDF semantics | I | Transparency, mixed page sizes, embedded images and documented annotation/form behavior match the supported visual contract. |
| [ ] | M2-AC04 | One-bit layout | A | MSB-first top-down 1=black layout, stride and white tail bits pass adversarial widths including 1,7,8,9,811,812,813 dots. |
| [ ] | M2-AC05 | Exact preview | A | Preview reconstruction matches the complete encoder input byte-for-byte after unpack/repack. |
| [ ] | M2-AC06 | Graphics limits | A | Fields stay within documented/profile limits; reconstructed multi-band image has no missing/duplicated rows or seams. |
| [ ] | M2-AC07 | Compression | A | Every enabled encoding round-trips bit-exactly and rejects malformed/overflow/checksum vectors as applicable. |
| [ ] | M2-AC08 | Copies and output order | A | Job plans follow M1 ownership and shared examples; output format/quantity expansion occurs exactly once. |
| [ ] | M2-AC09 | Resource safety | A | Size/page/pixel/output limits, malformed/encrypted inputs, deadlines and cancellations fail without unbounded allocation or partial default delivery. |
| [ ] | M2-AC10 | CLI/filter contracts | I | CLI error codes and filter stdout/stderr behavior are tested; invalid jobs emit no printer payload in the default prepared mode. |
| [ ] | M2-AC11 | Physical image quality | H | Reference labels have correct size/orientation and readable text/barcodes on the declared hardware/media configuration. |
| [x] | M2-AC12 | Performance baseline | I | Release-mode latency, peak memory, output bytes and throughput are recorded on a named reference Mac with reproducible fixtures. Evidence: [2026-09-15 offline baseline](../../validation/M2-PERFORMANCE-BASELINE-2026-09-15.md). |
| [ ] | M2-AC13 | GC420d dot-pitch oracle | A | Reference physical arithmetic produces 813×1219/102-row-bytes/124338 bytes with correct padding and band reconstruction; nominal integer DPI, head width, liner and gap are not conflated. |

## Completion rules

Check an item only after its exact evidence is recorded. Implemented is not physically tested. Account-free local signing is the active mode; future Developer-ID notarization is not an S1 blocker. Scope-specific nonapplicability is recorded with reasons and never silently becomes a global pass. Critical security, clipping, count/order or uncontrolled-replay defects block qualification. Use the [evidence template](../../validation/EVIDENCE-TEMPLATE.md), [progress](../../PROGRESS.json) and [scope status](../../SCOPE-STATUS.json).

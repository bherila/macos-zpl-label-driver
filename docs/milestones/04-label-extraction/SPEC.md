# M4 — Sheet extraction and browser workflows

**Dependencies:** M2 engine; M1 workflow media behavior; M3 profile/control integration
**Goal:** Extract, rotate, scale and order labels from larger documents without sacrificing source detail or silently discarding content.

## Profile-based extraction

Implement native-size, explicit template and teach-once extraction workflows. Input page size and physical stock remain separate. A profile contains expected upright page geometry, stable normalized regions, rotation, uniform scale policy, output stock/printable region, margins, source/output order, validation anchors and non-label-page handling.

Support one or multiple regions per page and multiple source pages. Render each final region from the original document. Validate profile regions, aspect ratio, quiet-zone margins and output fit. Do not deduplicate similar labels, stretch barcodes nonuniformly or drop blank-looking pages without an explicit policy.

A4 and Letter are distinct expected inputs. If orientation is permitted to vary, transform using the canonical geometry contract rather than swapping width/height heuristically. Mixed-size inputs require per-page matches or a clear mismatch. Non-label pages such as customs forms or instructions must be held/routed/skipped only under an explicit rule with a visible count; the default is review/error before any output.

## Teach-once editor

Build reusable SwiftUI/AppKit editor components that M5 integrates into the main app. Load a user-selected document, show its source page, allow bounded region selection/reordering, set rotation/output stock and show the exact final bitmap preview. Use explicit mm/in units and printer-dot diagnostics where helpful. Save an immutable validated profile revision, not mutable coordinates tied to a temporary thumbnail.

Import/export profile JSON contains no embedded shipping document by default. Imported profiles are untrusted and cannot contain shell/ZPL scripts or arbitrary file references. The editor must be keyboard-accessible and not rely only on color for mismatch feedback.

## Assisted detection and unattended operation

Add local heuristic detection using layout/whitespace/borders and optionally Vision barcode locations. Use an OS-available Vision API adapter; no cloud or LLM. Barcode bounds are only candidate evidence, not the full shipping label boundary. Do not decode then replace a carrier barcode as part of extraction.

Classify candidate outcomes as matched, no match or ambiguous. Require user confirmation when creating a new profile. Automatic unattended matching is enabled only for a qualified profile with explicit structural checks. A changed layout must fail/hold with an actionable message, not confidently print a clipped label.

Job titles/browser names are not reliable carrier identifiers. Avoid hardcoded 'all UPS/FedEx works' claims. Template presets should have layout/version metadata and synthetic/cleared regression documents. Detection may use a thumbnail, but final output may not.

## Virtual workflow queues

Provide configuration bindings for native-size, Letter extraction and A4 extraction queues targeting the same physical printer. Profile selection must round-trip through per-job controls or named workflows proven in M1. Test that app-facing page size is preserved. Update queue defaults transactionally and keep queued jobs bound to their original profile revision.

## Recovery

A mismatch surfaces a safe error and an editor/review entry through the companion app; a filter must not launch a GUI. Explicit user correction generates a new profile/reviewed job; it must not automatically duplicate output from an uncertain physical transmission. Distinguish an input-validation failure with no bytes emitted from a partially delivered job.

## First three workflow profiles

Create named `native-4x6`, `letter-to-4x6` and `a4-to-4x6` workflow definitions for the GC420d setup. Letter/A4 are application-facing source sheets; the physical stock remains 4×6 pre-cut media. Until layout validators or teach-once regions exist, mark extraction profiles incomplete and do not automatically guess a carrier crop. Generic source sheets must not be advertised as supported UPS/FedEx templates without actual layout evidence.

Use synthetic fixtures while real failing documents are unavailable. Real shipping labels/addresses remain private; sanitized input must be created safely at source. Apply the physical-pitch oracle through the extraction transform without reusing a thumbnail as output. Require application paths on Tahoe, not older-OS compatibility adapters.

## Related documents

Read [acceptance](ACCEPTANCE.md), [instructions](INSTRUCTIONS.md) and [validation](VALIDATION.md). Shared [contracts](../../CONTRACTS.md), [sprint baseline](../../SPRINT-BASELINE.md), [local signing](../../LOCAL-SIGNING.md), [release scopes](../../RELEASE-SCOPES.md) and [validation policy](../../VALIDATION-PLAN.md) apply.

## Primary references

[R02](../../REFERENCES.md#r02), [R03](../../REFERENCES.md#r03), [R08](../../REFERENCES.md#r08), [R10](../../REFERENCES.md#r10), [R26](../../REFERENCES.md#r26). Documentation supports APIs/model facts, not unperformed runtime or physical tests.

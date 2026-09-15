# M1 — macOS printing integration proof

**Dependencies:** M0; local Tahoe 26 Mac for GUI/scheduler/no-account installation evidence
**Goal:** Prove full-page capture, native per-job controls and local-signing installation/runtime feasibility before committing to an adapter.

## Scope

Build an instrumentation-first queue/filter experiment on a disposable or explicitly approved Mac. Its backend is an inert capture sink by default, not the user's printer. The test queue must be clearly named and removable. Preserve the existing working Zebra queue, default printer and unrelated CUPS settings.

Prototype a native Swift CUPS executable with the actual job ABI, correct stdin/file handling, separate stderr diagnostics, cancellation and failure exits. Record incoming MIME type, selected page boxes, dimensions, rotation, options, copies and filter-chain provenance without recording private document contents by default. Use synthetic PDFs and a synthetic HTML shipping-sheet page. Capturing full payloads is opt-in and local.

Generate a minimal original PPD describing native label media and a separate Letter/A4 extraction workflow. Include representative typed options for speed, darkness, finishing, stock, extraction, rotation and scaling. Generic system-rendered Printer Features is the hypothesis; no custom PDE or injection into browser UI. Source documentation is not current-OS evidence.

## Required experiments

Test Preview, Safari, Chrome and Firefox through the system print dialog. Separately record what browser-owned preview controls expose. Confirm that a Letter/A4 workflow delivers the entire page including corner registration markers rather than an upstream-cropped label. Do not assume the selected queue always receives PDF or that it retains vectors; inspect the captured input. For each path, determine who has already applied ranges, copies, collation, scale, rotation and number-up.

Verify file ownership, library/runtime loading, profile reads and cancellation in scheduler context. A terminal invocation under the user's account is insufficient. Determine a safe supported installation path rather than copying old `/System` examples. Validate non-home shared configuration access and immutable profile revision binding. Queue-held jobs must not silently pick up a changed workflow definition.

## Adapter decision

Write an ADR with actual observed OS/application versions and all required feature outcomes. Compare the CUPS path against a PAPPL/IPP experiment only if needed to resolve a failure or clarify the long-term boundary. Do not implement a custom IPP server. IPP vendor options existing on the server do not prove macOS UI exposure.

The transport choice must have one real owner of device lifetime. Prove whether a backend/coordinator/delegating backend can acquire a cross-process device lock and preserve cancellation/exit/status semantics under the sandbox. A filter-only lock is not accepted. Reusing a working system USB backend is allowed only with an evidenced contract; no new USB stack is required merely because the Mac is ARM.

## Out of scope for this milestone

Production raster quality, physical finishing, polished setup UI, Developer-ID public distribution and broad support claims. Account-free installation/authorization feasibility is explicitly in scope even though final UX belongs to M5. Use a pass-through/capture test harness only under an explicit experimental name. It must reject real production printing until the engine and transport exist.

## Exit gate

Accept an adapter only if evidence supports the mandatory application-facing workflows and option paths. A blocked or failed proof is not a go decision. Continue portable M2 work while blocked, but keep the adapter ADR unresolved and do not build a release installer around an unproven path.

## Tahoe, GC420d and local-signing proof

Use local ad-hoc signing with no Apple identity for the installed capture executable and proposed helper/installer. Exercise the real spooler after UI exit and a planned restart; code verification or user-shell execution alone is insufficient. Prove a supported narrow authorization/code-validation mechanism without Team-ID assumptions. Record OS approval requirements and tamper/substitution outcomes; do not weaken root-client authentication or require notarization to unblock the spike. See [local signing](../../LOCAL-SIGNING.md).

Prioritize actual GC420d USB delivery-boundary feasibility while the default sink remains inert. The named real configuration supports only direct thermal/tear-off here. Representative cutter/peeler option propagation may be tested on a clearly simulated inert capability profile, never by enabling those operations for the physical target. Test non-default speed/darkness option propagation without assuming current unit defaults.

Run native 4×6, Letter and A4 capture on the actual Tahoe host; record integer advertised DPI versus preserved document/physical geometry. Do not equate an integer 203-DPI raster with documented 8-dot/mm coordinates. [First-run plan](../../validation/GC420D-TAHOE-FIRST-RUN.md) separates host-only capture from any later authorized device access.

## Related documents

Read [acceptance](ACCEPTANCE.md), [instructions](INSTRUCTIONS.md) and [validation](VALIDATION.md). Shared [contracts](../../CONTRACTS.md), [sprint baseline](../../SPRINT-BASELINE.md), [local signing](../../LOCAL-SIGNING.md), [release scopes](../../RELEASE-SCOPES.md) and [validation policy](../../VALIDATION-PLAN.md) apply.

## Primary references

[R01](../../REFERENCES.md#r01), [R02](../../REFERENCES.md#r02), [R03](../../REFERENCES.md#r03), [R04](../../REFERENCES.md#r04), [R13](../../REFERENCES.md#r13), [R21](../../REFERENCES.md#r21), [R26](../../REFERENCES.md#r26), [R28](../../REFERENCES.md#r28), [R29](../../REFERENCES.md#r29), [R30](../../REFERENCES.md#r30). Documentation supports APIs/model facts, not unperformed runtime or physical tests.

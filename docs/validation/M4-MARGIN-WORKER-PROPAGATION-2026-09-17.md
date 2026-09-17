# Immutable margins through the private worker — 2026-09-17

Evaluated local unpublished source 6bfa0232a22349782c35c3b118babf0fa1be9ce1.

## Implemented behavior and constraints
Private OfflineConversionTicket version3 requires extraction and explicit outputMargins with exactly four finite nonnegative millimeter fields left/top/right/bottom. It rejects physically empty inset stock; placement retains quantized-area checks. Versions1/2 remain zero-margin and reject a margins field, including null. Integer-token validation remains unchanged. Unknown ticket version test now uses4 because3 is implemented; the original3 rejection still occurs as malformed when missing margins.

OfflineConversion binds ticket margins to original-PDF rendering. Both QuartzPlannedExtraction and OfflineExtractionWorker bind immutable planned-label margins. Nonzero subprocess requests use version3; zero retains the original version2 shape. Removed temporary unsupported-margin guards only after direct/worker propagation was implemented together. Stock mismatch still rejects both paths before parsing/child launch. Queue workflow-v3 admission remains disabled; no editable margin UI added.

Nearest independent constraints: original-source worker isolation, exact packed preview/encoder equality, legacy schema behavior and stock identity. Real native-vector fixture original PDF exercises private worker PBM/ZPL equality against direct rendering, and both planned parent bitmaps equal the direct bitmap. Every reserved-margin bit is blank; separate preceding renderer receipt checks an independent full packed rectangle for asymmetric/non-square-pitch fit and actual-size. Ticket tests reject null, bool, negative, missing, extra and physically empty margin fields; old version rejects field and old version1 decodes zero. Parent stock mismatch test remains admission-before-parse/launch.

## Actual validation
Final53focused native tests passed debug and release, own exits0: /tmp/zpl-margin-workflow-debug.log and /tmp/zpl-margin-workflow-release.log. Includes real bounded subprocess calls with5second deadlines, worker protocol admission, original PDF renderer/CLI and planned parents. Prior intermediate ticket-only53both passed, not substituted for final source.106Python tests passed /tmp/zpl-margin-ticket-python.log; subsequent edits are native source/tests/contracts only. Repository preflight and diff check passed on final source. Initial new ticket version caused the existing unknown-version3 expected-error assertion to mismatch (malformed rather than unsupported); moved unknown fixture to4, preserving unknown-version rejection and explicit malformed3 coverage. No pre-fix behavioral proof claimed.

Core source unchanged since309Core both-mode immutable-definition validation. Full native/accelerator/signature/packaging/current Linux/GUI/VoiceOver/scheduler/administrator/physical checks NOT RUN. No whole acceptance or ledger refresh; no new queue/device/privilege operation, source push, merge, stack conversion or publishing. Frozen full380native/Linux305Core checkpoint77de47c and PartB52ba93f remain unchanged and historical.

## Next step
Extend workflow-v3 immutable references and their queue/job/finishing reconstruction paths with compatibility/snapshot tests; add editor margin mutation and generation-bound review invalidation, then native controls. Run integrated native gate/signatures/packaged worker checks before claiming current software baseline. Manual installation/GUI/hardware gates remain open.

## File SHA256
- `Packages/LabelMac/Sources/LabelMac/OfflineConversion.swift`: `e5050710c054b3cee95e5a7e526d2e3415d53bae96f90a1f1a95457a52f2958b`
- `Packages/LabelMac/Sources/LabelMac/OfflineExtractionWorker.swift`: `71629b3ff320cb751da99e87e3f32eb8f7e5871e727a7403070a504619ed717d`
- `Packages/LabelMac/Sources/LabelMac/QuartzPlannedExtraction.swift`: `6812b237b6bdae221da3e742d2689f0132e7ea75ad886c9b75bee36c9d06a96d`
- `Packages/LabelMac/Tests/LabelMacTests/OfflineRenderWorkerTests.swift`: `1bc7e436914a5d55bcdaf3dd55fa32a242f720f77404638fd3e055b41a2170e9`
- `Packages/LabelMac/Tests/LabelMacTests/QuartzPDFRendererTests.swift`: `f26acf06b13c06cc2dbe6e7ddb476d1ace5d3c4538ac7108bf1f8118b7f88998`
- `Packages/LabelMac/Tests/LabelMacTests/QuartzPlannedExtractionTests.swift`: `edcacb7d5355e5ac4107678fbab1652271f1b0036e2a907bf0e6260f556d4888`
- `docs/CONTRACTS.md`: `ee322addfd9f7c364fd0455398b17bee1990afd956e7eca58e6b592a9bca818c`

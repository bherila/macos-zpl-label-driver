# Shared publication diagnostic redaction — 2026-09-17

Evaluated local unpublished source `a5ee0f7eef8bb1f29de85e41a5f3f9fc5189deb4`. Advances privacy implementation; whole M3-AC12 and installed M5-AC09 acceptance remain unclaimed.

## Named constraint and implementation

All identity-bearing uncertain-publication errors must redact routine descriptions, reflection and nested structural dumps while preserving exact typed recovery references. Source inventory found six wrappers: VirtualQueueStore, WorkflowProfileStore, PrinterProfileStore, FinishingQueueStore, FinishingArtifactStore and AcceptedFinishingJobStore. Their four value types now conform to the existing RedactedDiagnosticValue protocol: ImmutablePublicationIdentity, FinishingQueueReference, FinishingArtifactReference and AcceptedFinishingReference. No enum case, typed field, identifier/hash value, constructor admission, codec, permission or retry policy changed. Redaction is not access control; explicit typed/private codec access remains possible.

The new regression enumerates all four direct values and all six wrappers, checks description/reflection/nested dump for both synthetic identifier and digest, verifies typed fields and exact error equality. Before fix: one test,60 failing assertions, exit1, zero unexpected failures.

## Actual validation

Final selected native suites passed96 tests debug and96 release: PublicationDiagnosticRedactionTests(1), FinishingQueueStoreTests(36), PrinterProfileStoreTests(9), VirtualQueueStoreTests(10), WorkflowEditorTests(19), WorkflowProfileStoreTests(21). Two initial filter alternatives named nonexistent test classes and contributed no evidence. Actual ProfileBoundFinishingJobPlanTests then passed9 tests in each mode, covering artifact and accepted-job paths. Total105 distinct native tests per mode, command exits0. Existing publication fault/canonical-record/typed recovery tests preserve their byte/hash and uncertainty oracles.

Repository preflight,106 Python tests and diff check exited0. Logs `/tmp/zpl-publication-redaction-before.log`, `debug.log`, `release.log`, `finishing-debug.log`, `finishing-release.log`, `preflight.log`, `python.log` (latter names share `/tmp/zpl-publication-redaction-` prefix). Manual diff/disclosure reading confirmed existing redaction protocol plus synthetic identifiers/digest only.

Core/accelerator/full native CI/signature/packaging tests NOT RUN for this native-only reflection change. The preceding complete374-native baseline/app/Linux archive stays bound to its older source and is not relabeled current. No fixture/oracle/encoder changes, ledger acceptance refresh, queue/privilege/device operation, merge or publication. GUI/VoiceOver, actual minimum-runtime26, production scheduler/helper/USB and physical/release gates remain open; frozen PartB candidate unchanged. Next: finish implemented privacy/source-integration review and requirement reconciliation without replacing missing manual evidence.

## Implementation digests

- `Packages/LabelMac/Sources/LabelMac/PrivateImmutableDirectory.swift`: `039e0e99b33a2d03c1f5ac59c5e30e8915342a6e440bfde3259720453ef27188`
- `Packages/LabelMac/Sources/LabelMac/FinishingQueueStore.swift`: `d5f1b390f661dc6de88812ba93f625b8a3081c37f55b468717b6960a55a5b74f`
- `Packages/LabelMac/Sources/LabelMac/FinishingArtifactStore.swift`: `aadb89808901fbc9b9b96efd58ab9054f783de26c0cd2517d1eb9e349379a1b5`
- `Packages/LabelMac/Sources/LabelMac/AcceptedFinishingJobStore.swift`: `d29606ccb3061caa6b10e9046e4167f7a2e2f36389fd2cb44d81b667ccc6de2a`
- `Packages/LabelMac/Tests/LabelMacTests/PublicationDiagnosticRedactionTests.swift`: `9be9261d4bd74bf960220d02f8d77a07c7bccb4049458d8f1bc003c10f0ccf19`

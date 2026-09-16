# Native workflow definition transfer

Partial M4-AC06/08/12 and M5-AC10 implementation/automated evidence only.
No GUI, queue, installer, scheduler or physical result is added.

Setup connects Import Workflow JSON and Export Selected Saved Revision through
native file importer/exporter adapters. Import accepts only a local regular file
using the existing nonblocking no-follow descriptor reader, capped at 256 KiB.
The exact version-2 decoder rejects malformed, unsupported-schema and unknown
fields. It creates a fresh local identity at revision 1, preserving output stock,
physical geometry, regions, order, anchors, explicit skips and imaging policy.
It never replaces the current editor or copies any unattended qualification.
The user must open an original PDF and review before separately approving.

Publication reuses the immutable store and its uncertainty contract. Cancellation
before publication leaves no accepted import; once publication is admitted its
outcome is finished/reported rather than equating cancellation with absence.
An uncertain publication retains the exact candidate in this running model,
disables creating another import and exposes Reconcile Import. Reconciliation
retries that candidate's exact immutable publication/barrier, never a new UUID.
Repeated barrier failure retains uncertainty; successful recovery clears it.
Catalog visibility alone is not durability confirmation. This in-process candidate
is not a restart-recovery journal; interrupted-session reconciliation remains a
separate lifecycle task. A catalogue refresh failure after successful publication
is reported separately, not misdescribed as an absent import.

Export loads the exact saved revision from this model's own trusted store and
compares the canonical snapshot before presenting a write dialog. Its export-only
FileDocument contains only canonical profile JSON, no PDF, paths, qualification,
logs or printer commands. User-chosen identifiers/settings can still be sensitive:
the UI warns to review before sharing. Default filename is generic. Native file
export completion is not a spool durability or atomic/power-loss guarantee; a
write error says transfer did not complete, not that no partial file exists.

Nineteen focused native tests passed: five transfer and fourteen document-opening.
Regressions check fresh identity and preserved definition/imaging values, source
approval retained/import approval absent, malformed/oversized/unknown-field/schema,
non-file URL, directory and symlink rejection, exact/cross-store/tampered export,
cancel-before-publication and actual directory-sync failure with repeated exact
reconciliation. A connected synthetic PDF/real-worker test preserves the active
editor, original packed preview and saved approval through successful and failed
transfers. Existing hard-timeout FIFO tests exercise the reused reader.
The initial compile-only probe selected zero tests and is not counted as a pass.
At implementation `8067779`, full local gate passed exit 0: 67 Python/173 Core/
216 Mac tests debug/release; both accelerator suites, independent/inert checks,
local executable/app/nested-worker signatures and packaged-worker PBM/ZPL equality.
PR #58's same-branch correction is now integrated from `a1e1f58`: native UI
approval requires explicit bounds/displayed-packed-preview review for every
region of the complete current profile; editing/reopening/stale clicks cannot
bypass it. The connected transfer test uses this stricter throwing API and checks
the current editor's acknowledgement/approval remains valid after an import.
The parent's final local 67/173/212 gate passed; corrected hosted/second review
remain live. Run the combined gate before publication. Own hosted CI/review and
native dialog checks remain pending. After integration, 45 focused native tests
passed: fourteen editor, five transfer, fourteen document-opening and twelve
bootstrap. The transfer preservation test explicitly acknowledges the displayed
profile/packed preview before approval; imports preserve that current review state.

## Finite native validation — NOT RUN

Leave physical confirmations unchecked; do not install, submit jobs or print.
Open a committed synthetic PDF and save a workflow. Select that saved revision,
export to a chosen JSON file and inspect that it contains definition fields only.
Import it and verify a distinct local workflow is listed, the current editor is
unchanged and unattended approval is not inherited. Reopen the imported copy
against the same original PDF and compare its exact packed preview. Reject one
malformed JSON and preserve existing workflows. Cancel one import/export dialog.
Check keyboard/VoiceOver labels and errors separately. Preserve unavailable
controls or dialog failures; compiled views/window counts are not GUI acceptance.

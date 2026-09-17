# Editor stock/canvas binding — 2026-09-17

Evaluated source `86ed0520a42d2cb1dbd64b3899c63075bb54d016`, local unpublished.

WorkflowEditorModel.setOutputStock validates the displayed binding, prepares a limit-preserving replacement canvas and validated candidate draft before committing either. Successful edits advance edit generation, invalidate review, cancel any preview request and clear saved state. Saved profile edits use the existing correction-revision path. reloadForCorrection also rebuilds the canvas for the loaded stock before replacing the draft.

Independent constraints exercised: source-sheet rules and immutable saved revision survive destination changes; invalid ID, excessive geometry and stale callback rejection preserve current profile/preview/generation; exact original-source previews resize to20×10 then restore10×10 on saved revision reload. A real-worker finite barrier regression completes an old-stock request after a resized preview exists and asserts it cannot overwrite the newer result.

Final WorkflowEditorTests:21debug and21release, zero failures, own exits0. Logs /tmp/zpl-editor-stock-final-debug.log and /tmp/zpl-editor-stock-release.log. Earlier20debug passed before adding the final concurrent stock test. Repository preflight and diff check passed. SwiftPM serialized the debug run behind the release build; no process was restarted due to the wait.

New model API; no before-fix behavioral failure run claimed. Full native/Core/accelerator/packaging/signature/Linux tests NOT RUN for this native model slice. GUI/VoiceOver, scheduler/administrator and physical tests NOT RUN. Native stock controls and coherent bootstrap supported-stock policy are still pending. No physical stock qualification, acceptance refresh, device/queue operation, merge or publication. Frozen Part B candidate unchanged.

# Saved finishing job inspection and export UI — 2026-09-17

Partial M5-AC09 software integration, not prescribed GUI/integration acceptance.
This slice does not advance M5-AC03 routine application printing.
The setup app opens an existing accepted finishing record using a native file chooser,
derives its typed reference, then performs full original-source/context validation before
showing scalar label/canvas/local-intent/cancellation information. Hardware completion
remains unknown and no automatic replay is authorized. No print action is exposed.

Packed preview export revalidates the exact saved job, prepares from retained original
source, and uses the bounded no-overwrite exporter. The user selects a parent folder;
a fresh named subfolder contains actual packed PBMs and their manifest. Errors do not
include source contents, paths, identifiers or worker diagnostics. Uncertain publication
explicitly instructs preservation/review of output. Existing output is preserved.

Nearest independent constraint: a cancelled or superseded async request cannot replace
newly verified selection or clear the newer request's busy state. Requests bind UUIDs and
worker cancellation; detached work cannot publish state without matching request ownership.
The regression holds the first operation at a finite barrier, cancels it, completes a new
selection, releases the older operation, and checks preserved new state. Actual worker
inspection/export checks exact PBM equality and summary preservation after export failure.

Draft model/view standalone type-check passed against current build modules. Initial
package test build failed because a semaphore wait was called directly from an async
closure; it now runs through a synchronous closure on a detached task. Corrected focused
34-case suite session63707 passed own exit0 in118.216 seconds under finite180-second timeout.
Request-ownership omission fault failed exit1 through the expected assertion. Source was
restored exactly; all34 restored cases passed own exit0. The full finite900-second Mac
gate passed own exit0 in session14214:104Python/281Core/358Mac debug/release,
strict/ASCII independent oracles, inert ABI/pipeline, ARM/minimum26 metadata,
local signatures, Developer-ID negative and packaged-worker equality. Artifact:
artifacts/setup-app.gLgyA5. The full gate uses a process-scoped idle-sleep
assertion (caffeinate -i) and process-group timeout cleanup; no test deadlines change.
Local unpublished implementation checkpoint `fb9b34345a234238844f8d0151e54c01d27a29bf`.

Coverage gap identified during the gate: the current stale-result regression releases the
old request after the new one completes. It does not exercise preservation of a newer
request while that request is still busy. A four-path regression is now integrated
(open/export success/failure), holding the new request pending while the old one finishes.
Setup initialization error descriptions are also replaced by generic local-storage wording
to avoid exposing private paths. Busy-ownership fault failed exit1 through the expected assertion. Exact restored three
model cases passed own exit0 in debug and release in finite session32129, including all
four old open/export success/failure paths while a new request stayed busy. Affected final
app build passed own exit0 with ARM/minimum26 metadata, local signatures and packaged-worker
equality; artifact artifacts/setup-app.KxC3wr. These post-gate changes have targeted evidence,
not a new359-case full-suite declaration. Local unpublished implementation checkpoint `fb9b34345a234238844f8d0151e54c01d27a29bf`.

Related selector full gate32797 failed an existing source-reference release test; unchanged
four-case release reproduction77654 passed. A long bounded-loopback duration suggests host
scheduling/suspension delay, but its cause is unconfirmed. Keep the failed result; no
acceptance criterion or deadline has been relaxed.

Actual GUI, native dialog interactions, keyboard/VoiceOver, minimum-runtime26, installed
scheduler/helper, retail launch policy and physical printer evidence remain NOT RUN for
this slice. Existing narrow reported Part A and frozen Part B are unchanged. No printer
I/O, privilege action, merge, publishing or new release occurred.

## Remaining native GUI checks — NOT RUN

Use synthetic records only and keep the frozen Part B candidate separate.

1. Open a valid saved accepted record. Confirm label count, canvas, local intent,
   cancellation and unknown hardware completion match the verified inspection result.
2. Select a wrong-identity, missing or damaged record. Confirm no verified summary or
   export action remains available and no private path/payload appears in the error.
3. Export packed previews into an owned writable parent folder. Confirm a new subfolder
   contains all actual label PBMs and the identity/hash manifest. These files contain
   label content: review before sharing. Nothing should be uploaded or printed.
4. Cancel opening/export and open a different record. Confirm late results do not replace
   the new selection. Preserve any output already published when cancellation occurred.
5. Check keyboard navigation and VoiceOver for chooser, progress/cancel, summary,
   export and error/status controls. Record actual results against the exact app build.
6. Confirm no queue/default changes, privilege prompts, status query or printer command
   occurred. Compilation and model tests do not establish these native dialog checks.

# Finishing CLI worker-admitted cancellation — 2026-09-17

Local unpublished correctness fix in both finishing-inspect and finishing-preview.
Worker-admitted cancellation propagates OfflineRenderWorkerProcess.Error.cancelled;
the routes previously recognized only AcceptedFinishingJob.Error.cancelled. Both error
types now produce exit130/CANCELLED, with generic messages and empty stdout.

Nearest independent constraint: cancellation classification must cover both command
routes after worker admission without masking output durability uncertainty. Preview's
commitUncertain catch remains earlier and preserves output/review need; no broad signal
flag or generic catch converts publication uncertainty to cancellation.

The regression runs the real executable from a private synthetic fixture with an inert
finite sibling worker. Its admission marker precedes SIGINT/SIGTERM; no parser, printer
API or device output is used by that worker. Each owned CLI has a finite15-second bound,
and the inert worker has a finite20-second lifetime. Four combinations check exit130,
CANCELLED JSON, empty stdout, no private path, no preview output and no delivery intent
or cancellation namespace creation. Before-fix run55293 failed exit1 with eight expected
assertions (exit65/INPUT_ERROR). Corrected CLI-focused suite47995 passed own exit0 in debug and release:two cases per
mode, covering four admitted cancellation combinations and actual repeated-export
refusal (exit73, preserved output). Finite180-second bounds per mode.

The preceding app gate14214 passed104Python/281Core/358Mac debug/release and independent/
inert/signature/packaged checks; it does not cover this later fix. App-specific post-gate
three model cases passed debug/release and final app build32129 passed; these are distinct
checkpoints. Source checkpoint pending. Later CLI signature verification is not claimed by the
preceding app-build evidence; no new full360-case suite declaration.

Installed scheduler, native GUI/accessibility, minimum-runtime26, identified USB unit/status,
retail launch/install policy and physical printing remain open. Frozen Part B unchanged.
No hardware command, privilege operation, merge, publishing or release occurred.

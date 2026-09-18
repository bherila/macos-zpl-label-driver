# Explicit non-label page handling in the editor

Partial connected M4-AC05/06/12 implementation/automated evidence, not a new
macOS GUI, scheduler, installation or physical acceptance claim.

The existing typed skip reasons and independent extraction/order planner are
reused. Each source page is listed with its region count or explicit skip reason.
Marking a page non-label requires a confirmation showing the page, reason and
loss of this draft's crop definitions. Confirmation binds the exact profile
snapshot: an obsolete dialog cannot discard newly edited crops. Geometry and
structural anchors are preserved and remain mandatory even for skipped pages.
The action never implies a policy for an unexpected future page.

Restoring a skipped page explicitly appends a new uniquely identified full-page
region at the end of global output order. It does not guess the removed crop;
the UI warns to set its bounds and inspect the exact preview. Earlier immutable
revisions remain available. Both operations invalidate previews and, after a saved
revision, use the trusted store's latest-observed correction revision. At least
one output region is required by the existing profile contract, so the last output
page cannot be skipped. Removing a page's last region still fails rather than
implicitly skipping. A customs form marked non-label is not printed by another
path; the confirmation and page summary disclose this.

Eight portable draft tests and twelve native editor tests passed. New regressions
cover skip reason reporting, canonical round-trip, global copies/order, explicit
full-page restoration, retained geometry/anchors, unexpected-page rejection and
unchanged drafts after invalid operations. Skipped-page missing-anchor and changed
geometry cases independently fail. The native test uses a two-page Core Graphics
synthetic document and the real worker to preview before skipping and after
restoration; saved original and skipped revisions remain unchanged. Stale
confirmation and last-output-page actions fail without mutation.

At implementation `207bdb6`, the full local gate passed with exit 0: 67 Python,
173 LabelCore and 210 LabelMac tests in debug/release; both accelerator suites,
independent round-trips and inert checks; local executable/app/nested-worker
signatures and packaged-worker PBM/ZPL equality. Own hosted/review pending.
Parent PR #57 hosted run 35088846529 passed exact `5d9c2c2` with 209 native
tests debug/release, signatures and packaged equality; its first review is clean.
The parent's subsequent `626122d` changes evidence only, not source; its own
docs-only CI remains pending. No oracle, renderer, schema,
transport, queue, privileged path or hardware setting changed.

## Finite manual validation — NOT RUN

Launch the locally built setup app. Leave physical confirmations unchecked; do
not install, submit jobs or print. Open a committed multipage synthetic PDF in
manual extraction mode. Review each page's source reference. Mark one non-label
with an explicit reason, cancel once and verify unchanged regions, then confirm
and verify its page remains listed with the reason. Verify the last output-page
action is unavailable. Restore the skipped page, inspect the appended full-page
region, set bounds, generate the exact preview and save/reopen a correction.
Check keyboard and VoiceOver operation separately. Preserve failures; neither
compiled views nor WindowServer window counts establish this procedure passed.

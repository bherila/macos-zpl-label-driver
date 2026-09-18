# Source-page drawn region selection

Partial M4-AC06/07/09 implementation; GUI acceptance remains unproven.

Dragging on the source reference updates canonical normalized extraction bounds
only on gesture completion. The gesture captures its region and viewport and
rejects changed ownership or viewport dimensions. Off-page endpoints are visibly
constrained to the page; off-page starts, empty drags and non-finite coordinates
are rejected. Reverse-direction and scaled-viewport drags preserve bounds.
The source display is never used as the final rendering source. Numerical
millimeter fields remain the keyboard path, and the exact packed preview is
invalidated after edits.

Editing a saved workflow creates its next immutable revision; repeated unsaved
edits retain that revision. Invalid edits do not alter the saved record or its
identity. Prior records remain loadable. This also fixes the numerical, rotation
and ordering edit paths after save.

Focused validation: two portable selection tests and ten native editor tests
passed, including stale ownership, invalid edits, saved numerical/drawn edits,
old revision preservation and existing real-worker exact-output comparisons.
At implementation `3c5b7d6`, the full local `bash scripts/ci-swift.sh` gate passed:
67 Python, 169 Core and 193 Mac tests in debug/release, 132 independent
ZPL/PBM/analytic round trips, 15 backend/10 filter/one inert pipeline cases,
ad-hoc executable/app/nested-worker signatures and packaged-worker equality.
Own hosted CI and independent review remain pending. PR #53 at `64a22f3` has passing hosted run
35082704430 and a clean independent review; these do not validate this new slice.

Finite manual procedure (NOT RUN): open one synthetic Letter PDF in manual mode,
show its source page, draw the same rectangle in both directions, resize the
window and repeat, compare numerical bounds, change selection during a drag,
and inspect the separate exact preview. Save, edit and save again; confirm the
old revision remains available. Check keyboard fields and VoiceOver labels.
Do not install queues or print during this procedure. No hardware, privilege,
installed scheduler or physical fidelity result is claimed.

# Connected multiple-region editor

Partial M4-AC03/06/07/12 implementation, not GUI or physical acceptance.

Add Region on This Page explicitly starts with the selected region's bounds and
rotation. It creates a distinct identity immediately after that region in the
global output order. A visible warning explains that each region produces a
label and requires explicit bounds. This is not automatic crop detection.
The user can draw or numerically edit the new region and reorder it.

Remove Region renumbers the global sequence and selects a remaining region on
the same page. Removing a page's last region is rejected: an implicit skip must
not arise from an editing action. Explicit page-handling UI remains future work.
Page geometry and structural expectations are preserved. Invalid/duplicate
identities and the public 256-region-per-page limit leave the draft unchanged;
additions must also fit the public JSON byte limit. Saved edits create one new
immutable revision, retaining old records and invalidating stale previews.

Six portable draft tests passed, including two new regressions for add/remove,
global order and uncollated copies across pages, canonical round trips, last-region
refusal, duplicate/missing identities and the per-page bound. Eleven native
editor tests passed. The added regression creates and adjusts a region, renders
its original-PDF crop through the real supervised child, verifies packed bytes
and PBM, reorders, saves/reloads, removes and verifies old immutable records.
No placeholder renderer, bitmap or independent validator was introduced.
Implementation `fafd7a13f2c03e011d99544c32de106ca015f14e` passed the full local
`bash scripts/ci-swift.sh` gate: 67 Python, 171 Core and 194 Mac tests in
debug/release, 132 independent round trips, 15 backend/10 filter/one inert
pipeline cases, executable/app/nested-worker ad-hoc signatures and packaged
worker PBM/ZPL equality. Own hosted CI and independent review are pending.
Parent PR #54 passed hosted run 35083659869 at exact `2bf83ba`; logs confirm
193 Mac debug/release tests and packaged-worker/signature checks. Its first
independent review is clean. These parent results do not validate this slice.

Finite GUI procedure (NOT RUN): open committed synthetic Letter 2-up input in
manual mode; set the first label's bounds; add a region, set the second label's
bounds, generate each exact preview, reorder, save and reload. Remove one region
and verify remaining order; verify last-region removal is disabled. Repeat with
the keyboard and VoiceOver. Use no queue installation or printer output.
No administrator, scheduler job, device command, label or hardware result used.

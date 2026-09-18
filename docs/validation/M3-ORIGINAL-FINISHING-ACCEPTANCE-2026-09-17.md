# Original-document finishing acceptance — 2026-09-17

Partial M3/M5 unprivileged software, not scheduler admission or hardware authority.
AcceptedFinishingJob has a factory-only public construction path and retains original PDF
bytes/hash, exact private queue/reference, complete workflow/profile/native geometry,
copy/range/transform ownership, expanded ExtractionPlan, finishing policy and resolved
controls. The fixed intake provenance is offlineCLI. Identity/cancellation hash,100MiB
source,1000pages/10000labels, finite60-second operation budget and cancellation are checked.
Queue/profile stores and geometry are independently revalidated. Invalid controls/selection
fail before PDF analysis. The isolated worker observes original pages/anchors, including
barcode-required pages; it cannot replace source identity with thumbnails.

Both ExtractionPlanner entry points now take optional selectedSourcePages. All source pages
remain accounted and geometry/anchors checked before filtering. Explicit ranges precede
copy expansion and retain only selected non-label dispositions; selected non-label pages
are valid range members without requiring a label on each page. Empty/out-of-range sets
fail invalidPageSelection. Default nil preserves existing behavior. Ownership preserves
whether upstream or engine applied ranges/copies, and downstream quantity stays unchanged.

Preparation receives only retained source/plan/geometry/conversion/controls. Its result must
match source hash/size, complete extraction/canvas and controls. There is no parameter to
replace an accepted source or control snapshot. Complete profile/order/framing evidence
remains in the existing preparation pipeline. This is an in-memory accepted value, not a
durable ticket schema, active finishing queue generation or permission to send to a device.

Nearest independent constraints: selected pages cannot hide unexpected input or invalid
unselected geometry; both planner entry points must preserve selection before expansion;
source identity and explicit controls cannot change while output count is held fixed.
Eight Core focused/restored cases passed exit0, covering both entry points, collated and
uncollated expansion, mixed label/non-label ranges, unselected non-label exclusion,
unexpected source, unselected geometry and invalid ranges. Removing range forwarding,
label filtering or skipped-page filtering independently failed exit1; exact source restored.
Ten native focused/restored cases passed exit0, including real isolated analysis of the
synthetic native-vector PDF, two crop regions, both copy orders, four output labels and
batch cut boundaries[3,4], explicit darkness0 over workflow9, original hash/bytes,
original-source raster preparation, invalid controls before a nonexistent worker,
duplicate/out-of-range ownership and precancel rejection. Removing copy ownership,
explicit control requests or original source hash independently produced expected assertion
failures exit1; exact source restored and all ten passed exit0. No physical output occurred.
Logs /tmp/zpl-extraction-page-ranges-focused.log,
/tmp/zpl-extraction-page-ranges-{entry-forwarding,label-filter,skipped-filter}-fault.log,
/tmp/zpl-extraction-page-ranges-restored.log, /tmp/zpl-accepted-finishing-focused.log,
/tmp/zpl-accepted-finishing-{copy-ownership,control-request,source-hash}-fault.log and
/tmp/zpl-accepted-finishing-restored.log.
AcceptedFinishingJob source SHA256: 7ffc202b170c896aa5e91fb902c76ef26cf23afde9997acbd5c9a91bc0b27ff6.
ExtractionPlan source SHA256: 48563bf92f1ccc12ac0bd594904095ee48ae5193385e18873ac426caf40cd771.
Full finite900s gate session88103 completed FULL_GATE_EXIT0:104Python/281Core/334Mac
in debug/release plus strict/ASCII oracles, finite inert ABI/filter/pipeline checks,
ARM/min26 metadata, nested local signatures and packaged-worker PBM/ZPL equality.
Log /tmp/zpl-accepted-finishing-full.log; artifact artifacts/setup-app.B7XMVz.
Both library files/tests are included by existing CI. Implementation checkpoint ccd7a9aab1175518fda1a8db783862ed865b1d81; source publication pending.

Next: canonical durable finishing ticket/original-source publication, complete accepted
identity linking into framing/attempt intent, cancellation and lifecycle recovery. Actual
unit correspondence/status, scheduler/privileged admission, retail policy and physical
qualification remain open. Frozen Part B unchanged. No administrator, printer I/O, merge
or binary publication action.

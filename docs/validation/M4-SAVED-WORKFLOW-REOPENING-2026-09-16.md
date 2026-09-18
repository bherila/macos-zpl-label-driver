# Saved workflow reopening in setup

Partial M4-AC01/06/07/12 implementation and automated evidence; GUI acceptance
remains NOT RUN. No scheduler, privilege, transport or printer I/O is added.

Setup lists saved immutable revisions, lets the user choose a revision and local
source PDF, and opens a new unsaved correction revision. Catalog enumeration
runs off the main actor against one validated directory descriptor, with at most
4096 namespace entries, 256 records, 256 KiB per record and 64 MiB total bytes.
Hidden unpublished staging names are ignored, not removed or accepted. Candidate
JSON must be canonical and match its hash/revision filename. Unsafe, malformed,
misnamed or over-budget candidates fail the catalog rather than silently omitting
workflows. This is a bounded listing, not a namespace-wide atomic snapshot.

The exact selected profile is reloaded and compared with its catalog snapshot
before reading the PDF. The existing supervised layout worker analyzes original
bytes and the saved profile's required structural pages. The planner validates
all page accounting, geometry and anchors before installing an editor. No
assisted detection or fallback crop substitutes for the saved definition.
Changed layouts, extra pages and mismatched source geometry keep the existing
editor. The current setup only accepts its confirmed 4x6 output stock; a different
saved stock fails without clamping or modifying its immutable record.
Reload also rejects noncanonical records, including semantically equivalent
trailing whitespace. Missing, malformed and changed snapshots produce a saved
workflow verification error rather than misidentifying the PDF as the failure.
Manual workflows without anchors still require visual review; page geometry
alone does not establish layout identity.

Correction preserves profile identity and all rules, advances the revision once,
starts unsaved, and does not inherit old unattended qualification. Preview still
renders the original PDF through the real child and shows its exact packed
bitmap. Request ownership and cancellation guard completed obsolete opens.
The existing 60-second cooperative opening budget includes profile/PDF reading;
it is checked after filesystem operations, not a guarantee of interruptible disk
I/O. Worker-owned deadlines remain separate and active during native parsing.

Focused native validation: 48 tests passed (10 document-opening, 15 profile-store,
12 bootstrap and 11 editor). New regressions cover canonical revision catalogs,
unpublished staging, listing/byte bounds, misnamed/noncanonical/oversized records,
symlink/hard-link/directory rejection, FIFO catalog candidates with/without a
writer in two-second subprocess tests, exact original-source saved-crop reopening,
prior qualification preservation without inheritance, layout/geometry/extra-page
mismatch, cross-store snapshot rejection, output-stock mismatch and completed
stale saved-opening results and missing/malformed/noncanonical cached snapshots.
No placeholder renderer or validator was added. The first implementation
`3118dbb` passed the full local 67 Python/171 Core/203 Mac debug-release gate,
132 independent round trips, 15/10/one inert checks, ad-hoc app/worker signatures
and packaged-worker equality. The final canonical reload/error/copy correction
passes 48 focused tests; its full local gate and own hosted/review are pending.
The final implementation `b836b42c88243381ac46a25a436d249d53a1ade3` passed
`bash scripts/ci-swift.sh`: 67 Python, 171 Core and 204 Mac tests in debug/release,
132 independent round trips, 15/10/one inert checks, executable/app/nested-worker
ad-hoc signatures and packaged-worker equality. Own hosted/review remain pending.

Additional local native observation: `AXIsProcessTrusted()` returned true. A
finite helper launched the newly built ad-hoc setup executable as its own child,
observed an AX window, and terminated/reaped only that instance. It did not use
Launch Services, open a PDF, assert hardware facts or perform button actions.
The initial bounded traversal failed on repeated elements; a deduplicated version
then failed to locate all expected controls, including after a 15-second startup
wait. This is a failed/unresolved harness/control lookup, not a GUI pass or a
diagnosed product defect. No private UI dump was captured. Native accessibility
is available, but complete teach-once interaction remains unverified. Existing
offline-edit gating requires physical stock/tear-off confirmations; do not invent
those observations merely to test offline editing. Separating that gate and
resolving accessibility lookup are the next connected slice.

Parent PR #55 at `55dd7d2` has passing hosted run 35084288575 and a clean first
review. These do not establish this slice's hosted or GUI acceptance.

Finite GUI procedure (NOT RUN): open committed synthetic Letter input in manual
mode, set bounds, generate the exact preview and save. Refresh the list; close
and reopen setup, select the saved revision and the same synthetic PDF. Compare
bounds/preview, edit and save the correction, and confirm both revisions remain.
Reopen with A4 or changed-layout input and verify the prior draft is preserved.
Check picker, buttons and fields using keyboard/VoiceOver. Use no installation,
queue changes, output jobs or physical labels. Catalog pagination, explicit
non-label-page UI, imported/exported profiles and full GUI qualification remain
independent unfinished work.

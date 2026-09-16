# PR #58 review remediation: explicit exact-preview review

Second-pass finding 4025638071 exposed an unsaved edit/undo gap: returning to
the same profile value could resurrect an earlier acknowledgement. Every
successful draft mutation and reload now clears review state and advances a
checked edit generation. The displayed acknowledgement captures that generation
as well as the profile and packed preview. An old callback is rejected even if
later edits restore identical values. Invalid edits preserve valid review state.
The real-worker undo regression and 40 focused native tests passed. At
`501cdf1`, the full local gate passed exit 0: 67 Python, 173 LabelCore and
213 LabelMac tests in debug/release; both accelerator suites, 132 independent
round trips, 15/10/1 inert ABI/pipeline cases, local executable/app/nested-worker
signatures and packaged-worker PBM/ZPL equality. Corrected hosted CI remains
pending. No third review request
will be made; the second-pass correctness finding is being fixed on this branch.

Native editor source/automated evidence for finding 4025449342, not GUI,
physical-print or barcode acceptance. Fixed on PR #58's branch, not deferred.

The initial restored-region warning was not enforced by the approval path.
The editor now requires an explicit Confirm Bounds and Exact Preview Reviewed
action for each output region of the exact current profile before native-UI
unattended approval. The action requires the current selected region's prepared
packed preview, matching region/source page/profile identity and revision.
Preview generation alone is not acknowledgement. The same predicate controls
the button and throwing model API; saving alone does not grant approval.
The button captures its displayed full profile and prepared-label value. The API
compares both against current state before acknowledging; a stale click cannot
review a newer profile, region selection or unseen bitmap.
Structural checks and exact own-store qualification binding remain mandatory.

Acknowledgements bind the complete current profile value, not just a region ID
or full-page shape. Any profile edit/revision change makes them stale. Every new
editor starts unreviewed, and reopening/reload produces a new unreviewed revision;
saving, modifying bounds or reopening cannot bypass the gate. Review covers all
regions rather than a fragile restored-ID convention or inferred full-page flag.
Legitimate full-page labels can be reviewed without inventing a coordinate edit.
This is a native-UI session review gate, not a persisted evidence journal or a
claim that trusted low-level user-confirmation APIs provide physical validation.
Existing exact old revision qualifications are not silently revoked or inherited
by new revisions. Imports remain separate from qualification.

39 focused native tests passed: 14 editor, 13 document-opening and 12 bootstrap.
The two-page restore regression reviews one region, keeps approval unavailable,
reviews the other, then qualifies; reopening/saving again requires both reviews
and preserves the earlier qualification. A new real-worker regression rejects
acknowledgement without preview, requires explicit acknowledgement after preview,
and makes a rotation edit invalidate prior review before requalification.
Existing manual/no-anchor rejection and immutable-source/preview/history tests
remain intact.
The displayed-snapshot regression rejects old profile and old-selection previews
after real-worker completion without acknowledging any region, then accepts the
current displayed snapshot. Initial correction `5fb351e` passed the full local
gate exit 0 with 67/173/211 debug/release, independent/inert/signature and packaged
worker equality checks. Final displayed-snapshot implementation `a51780f` then
passed the full local gate exit 0 with 67 Python/173 LabelCore/212 LabelMac tests
in debug/release, both accelerator suites and independent/inert checks, local
executable/app/nested-worker signatures and packaged-worker PBM/ZPL equality.
Hosted run 35091595114 passed exact `a1e1f58`; it precedes the second-pass undo
correction above. The second review found 4025638071, not a clean pass. This is not native
dialog/VoiceOver or physical acceptance.

No profile schema, oracle, renderer, transport, queue, privileged or hardware
setting changed. Native button/VoiceOver operation remains NOT RUN. Extend the
finite page-handling manual procedure to verify preview alone does not enable
approval, each region must be acknowledged, and editing/reopening disables it.

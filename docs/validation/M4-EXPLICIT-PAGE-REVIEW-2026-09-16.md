# PR #58 first-review remediation: explicit exact-preview review

Native editor source/automated evidence for finding 4025449342, not GUI,
physical-print or barcode acceptance. Fixed on PR #58's branch, not deferred.

The initial restored-region warning was not enforced by the approval path.
The editor now requires an explicit Confirm Bounds and Exact Preview Reviewed
action for each output region of the exact current profile before native-UI
unattended approval. The action requires the current selected region's prepared
packed preview, matching region/source page/profile identity and revision.
Preview generation alone is not acknowledgement. The same predicate controls
the button and throwing model API; saving alone does not grant approval.
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

38 focused native tests passed: 13 editor, 13 document-opening and 12 bootstrap.
The two-page restore regression reviews one region, keeps approval unavailable,
reviews the other, then qualifies; reopening/saving again requires both reviews
and preserves the earlier qualification. A new real-worker regression rejects
acknowledgement without preview, requires explicit acknowledgement after preview,
and makes a rotation edit invalidate prior review before requalification.
Existing manual/no-anchor rejection and immutable-source/preview/history tests
remain intact. Full local corrected gate and second review/hosted CI pending.

No profile schema, oracle, renderer, transport, queue, privileged or hardware
setting changed. Native button/VoiceOver operation remains NOT RUN. Extend the
finite page-handling manual procedure to verify preview alone does not enable
approval, each region must be acknowledged, and editing/reopening disables it.

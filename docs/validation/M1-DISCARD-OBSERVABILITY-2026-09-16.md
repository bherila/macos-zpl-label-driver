# Discard-only warning at normal scheduler logging level

Implementation/automated preparation for M1-AC01/04/08/09/11/13 only.
Administrator installation and all installed-scheduler criteria remain NOT RUN.

Read-only inspection observed `LogLevel warn` on this macOS 26.6.2 / 25G83 ARM
host. R39 documents that the previous INFO metadata report is error-log-visible
only at debug2. The finite administrator procedure forbids enabling global
verbose/payload logging. Depending on that INFO record was therefore not a sound
observability prerequisite at the observed configuration.

The inert capture filter now emits one `WARNING: LABEL_CAPTURE_FILTER` line
after successful bounded pass-through. This is a genuine warning that the
experiment discards physical output, not a fabricated filter error: exit remains
zero for inert success. Schema 2 adds the positive numeric job ID already
validated by the ABI and a fixed discard-only audit reason. Metadata remains
allowlisted: no title, username, raw document, bitmap, private path, endpoint or
unknown options. It is not used by ordinary production printing. Failure paths
must not emit successful observation metadata.

The supplied finite filter ABI harness now asserts the exact report field set,
schema/job binding, fixed audit reason, one bounded line, intact stdout and
private-marker exclusion. It adds the exact one-copy/four-option administrator
tokens and rejects job ID zero with zero stdout. The real filter-to-inert-probe
pipeline uses the new warning prefix while the separate probe remains unchanged.
No bitmap/graphic writer/order planner/independent decoder is replaced.

Before edits the offline accelerator passed exit 0 with 132 independent round
trips, 15 backend ABI, 10 filter ABI and one inert pipeline. New focused and full
gates are pending at this source checkpoint. The new focused build passed;
all 12 filter ABI/negative cases and the one real inert pipeline passed exit 0.
The final failure-marker assertion was exercised by the full gate.

Full local gate at `a5fa6141a66c985c566e8c1b05a9064edec99237` passed exit 0:
`bash scripts/ci-swift.sh` under a finite 1200-second outer limit; 67 Python,
178 Core and 258 Mac debug/release tests, both accelerator configurations,
132 independent round trips and 15 backend/12 filter/one inert pipeline cases
per mode passed. Local-ad-hoc ARM/minimum-26 executable/app/nested-worker checks
and packaged-worker PBM/ZPL equality passed. The app artifact is local only,
`artifacts/setup-app.Saihmt/Label Printer Driver Setup.app`; it does not replace
the maintainer's separately pinned manual GUI artifact. Publication edits are
documentation/manifest only. Own hosted CI and correctness review await
publication; no new execution snapshot is approved yet.

Parent PR #71 exact `889472c803fa1e07aba60c0c97817b0bdf8ea9f8` hosted run
35111712826 passed. Fetched logs verify 178 Core/258 Mac debug/release, local
signatures and packaged-worker PBM/ZPL equality, including final-dot synthetic
Code128/QR decoding. No physical or installed-scheduler result is inferred.

No traditional filesystem CUPS error log was present. A marker-only cupsd
unified-log query under a hard 15-second process limit completed successfully
with no events before any job. This is query availability, NOT a warning-routing
or filter-invocation pass. Missing/overwritten/redacted correlation at the actual
experiment is inconclusive, not a reason to change global logging or replay jobs.
Only finite owned-job marker results may be retained locally; public evidence
uses sanitized counts, not local job IDs or unrelated log contents.

The earlier private pre-administrator snapshot is explicitly marked superseded
for execution and its original bytes retained. The script/PPD candidates are
unchanged. After review and full checks, freeze a new validated binary identity
before applying anything. The finite budget remains one held synthetic PDF,
one release, at most 60 seconds observation, immediate ownership-aware removal,
and zero physical labels. Actual log routing, administrator admission and the
production scheduler/worker identity/access architecture remain unproven.

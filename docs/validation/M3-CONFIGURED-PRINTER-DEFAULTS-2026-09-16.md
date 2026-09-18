# Immutable configured printer defaults

Additional partial M3-AC02/03/13 and M5-AC04/05/07 implementation/automated evidence.
No scheduler/default-dialog or physical control acceptance.

Private printer profiles now support versions 1 and 2. Version 1 retains its
exact six-field canonical JSON shape and empty configured defaults. Version 2
adds a required exact object containing nullable thermal method, finishing and
print speed. The existing control validator rejects unsupported choices and
unqualified darkness, tracking and media geometry; a version change does not
authorize commands. The GC420d reference factory remains version 1/unobserved.
No existing revisions, digests or queues are silently rewritten.

Resolution now implements explicit job > immutable workflow > immutable printer
defaults, excluding read-only observations. The existing accepted-ticket,
profile-reference, complete prepared artifact and encoder paths are reused.
Accepted-ticket version 2 permits only supported printer schemas 1 and 2 and
still checks resolved-control schema/revision agreement. Explicit profile lookup
checks the full schema/revision/digest; ID/revision-only lookup discovers the
decoder-validated actual schema rather than inventing version 1.

PASS: 35 focused portable tests including the final read-only observation
discriminator, exit 0.
PASS: 63 focused native accepted-job/printer-store/queue-store tests, exit 0.
The new persistence case initially failed because the ID/revision lookup assumed
version 1; the corrected real store path passes. It publishes a version-2 profile
with default speed 2, binds an accepted job, publishes speed 4 as a later revision
and changes the active queue, then publishes/reloads the older complete prepared
artifact. Its frozen controls and exact ZPL bytes retain speed 2. A falsely
relabeled schema reference fails. This uses the existing synthetic accepted-source
and bitmap fixtures to isolate policy/persistence, not to prove PDF imaging.

PASS: full local `bash scripts/ci-swift.sh` at `00180d3`, exit 0: 67 Python,
178 LabelCore and 248 LabelMac tests in debug/release, both accelerator modes,
132 independent round trips, inert ABI/filter pipeline checks, local-ad-hoc
ARM/minimum-26 executable/app/nested-worker signatures and packaged-worker
PBM/ZPL equality. Subsequent evidence-only edits undergo repository preflight.
Native environment: macOS 26.6.2 build 25G83, Apple Silicon, Swift 6.3.3.
Own hosted CI/review NOT RUN before publication. Actual system-default propagation,
installed scheduler, GUI editing of printer defaults and physical speed/settings
isolation remain NOT RUN. No queues installed, jobs submitted or device I/O.

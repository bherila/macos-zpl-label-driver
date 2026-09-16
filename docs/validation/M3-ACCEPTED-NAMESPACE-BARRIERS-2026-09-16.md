# Accepted-job namespace acknowledgement — 2026-09-16

Additional partial M3-AC12 evidence only. Production scheduler intake, installed
worker identity, USB, hardware and release acceptance remain NOT RUN.

## Contract and implementation

The accepted bundle's files and staging directory are synchronized before its
exclusive rename. Success now additionally requires the configured directory
barriers for `accepted-jobs`, its private store root, and that root's containing
directory, in that order. Identical retries repeat all three barriers without
replacing an advanced lifecycle record. A failed barrier is `commitUncertain`,
not evidence that the published name is absent or permission to discard/replay.

The retained accepted-jobs descriptor must still match the directory named under
the opened root, and that root must match its name under the opened containing
directory. Descriptor/name device-and-inode bindings are checked before and
after the barrier sequence. A detached/replaced namespace cannot acknowledge
the bundle simply because its old descriptor remains readable. No ambiguous
artifact or replacement is removed by this implementation.

The API creates only a root whose containing directory already exists; callers
must use an ordinary named root entry: final `.` and `..` aliases are rejected
before any accepted namespace creation, rather than silently normalized. Callers
must provision stable existing ancestry above that containing directory. This
slice does not implement a recursive installation/provisioning transaction or
authenticate arbitrary path ancestry. Checks are not a lease against later
cooperative namespace changes. Local filesystems must support the configured
directory barriers; unsupported/error results remain explicit uncertainty.

This is the platform `fsync` acknowledgement contract, not an unconditional
power-loss promise. Stronger device flushing and filesystem-specific crash
qualification remain distinct work. See R41 and the earlier idempotent acceptance
and immutable-configuration publication evidence.

## Actual evidence

Before affected work the offline accelerator exited 0: 132 independent round
trips, 15 backend/12 filter ABI cases and one inert pipeline. Existing supplied
bitmap, graphic writer, ordering planner, oracle and concrete fixtures are reused
unchanged.

Three new native regressions failed on the old implementation with nine
assertion failures: incomplete barrier sequences, persistent root/containing
sync failures incorrectly acknowledged on initial/identical publication, and
success after root replacement detached the bundle. Logs were retained locally.
After the correction all 51 accepted-store tests passed. A fourth regression
then replaced the root during the actual barrier sequence; all 52 accepted-store
tests passed. Tests identify the actual synchronized directory descriptors and
inject failure at the root or containing directory, rather than throwing an
unrelated post-rename exception. Successful calls use real native `fsync`.
Recoverable source bytes and advanced prepared state remain exact across retries.

The existing concurrent duplicate-writer gate now pauses only its first barrier
and has a finite five-second release bound, preserving the original admission
interleaving without blocking all three new calls indefinitely.

Full local gate at `5ff59b1f678179ec2d69841f4e16603bfab24e11` passed exit 0:
82 Python/178 Core/262 Mac debug/release, both independent accelerator runs,
15 backend/12 filter ABI cases and one inert pipeline per mode, local ad-hoc
ARM/minimum-26 signatures and packaged-worker exact PBM/ZPL equality. Own
hosted run 35118943004 passed at exact publication `a3952ba`; fetched logs
verify the same native counts, both independent/inert runs, signatures and
packaged equality. First review is clean at base `b4d78e8` / head `a3952ba`,
with reviewer thumbs-up and no findings/threads. No merge. Parent PR #73
latest `b4d78e8` hosted 35116981496 passed with inspected native/inert/signature/
packaged logs; its source review is clean at base `fa6c247` / head `03992fd`.
No administrator session, queue/job action or physical printer access occurred.

Next: continue the separate finite M1
administrator proof when its interactive OS authorization is available.

## Follow-up root-name regression

Native Foundation path inspection showed that a final `.` remains the last
component and deleting it can identify the root itself rather than its physical
containing directory. The new alias-construction regression reproduced three
failures: both dot aliases were accepted and an accepted-jobs directory was
created. An early named-entry guard fixes that boundary without changing an
existing directory or normalizing ambiguous caller intent. All 53 focused native
store tests passed after correction. This additional source guard is not covered
by the earlier 5ff59b1/a3952ba full/hosted/review checkpoints; its corrected full
gate and second review pass remain pending. Prior documentation head 6fe7508
hosted 35119811256 passed separately and is not alias-regression evidence.

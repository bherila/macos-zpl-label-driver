# M3 — private lease namespace admission

## Requirement and nearest independent constraint

Additional partial M3-AC07/08/12 automated evidence, not installed queue or
physical-device acceptance. The independent constraint is one named inode for
one physical-device coordination identity: validation may not admit a replaced
root/lock and must release the original kernel lease on rejection.

Previously the lease followed the final directory symlink, accepted loose root
and lock permissions/nonempty lock files, and opened through an absolute path
without rechecking named inode identity. The corrected acquisition opens the
existing directory without following its final symlink, validates effective-user
ownership and exact private 0700 mode, and opens the lock descriptor-relative
with no-follow/close-on-exec/nonblocking flags. Empty singly-linked regular locks
must be owned by the effective user with mode 0600. Root and named lock identities
are checked before and after nonblocking `flock`. Any failure closes the opened
lock descriptor, releasing a kernel lease if it was already acquired. Rejected
files/directories are never chmodded, truncated, unlinked or automatically repaired.

No directory is created by the lease API. The existing private inert fixtures
supply the intended namespace. Production root ownership/permissions and the
scheduler/helper authority remain an M1 admission decision, not inferred here.

## Actual evidence

- Old-code six-test suite: five assertion failures, exit 1. Loose permissions
  and nonempty lock content were accepted; a symlink root was followed and a
  new file created inside its target.
- Corrected eight-test `PhysicalDeviceLeaseTests`: pass, exit 0. Existing alias
  contention, explicit release/reacquisition, opaque names and real finite child
  termination tests remain green. Two deterministic replacement tests each run
  at opened and locked checkpoints. Detached root/lock detection rejects the
  attempt, leaves replacement namespace untouched, and subsequent reacquisition
  proves the original descriptor/lease was released.
- Required `bash scripts/ci-swift.sh`: PASS, exit 0 within the 900-second
  bound. 86 Python / 190 Core / 273 Mac tests pass in debug/release, including
  the persisted inert pipeline with the stricter lease policy. Original 132 /
  compressed 180 independent vectors, 15 inert ABI / 14 filter ABI / one discard
  pipeline per configuration, native builds, nested ad-hoc signatures, ARM /
  minimum-26 metadata and packaged worker PBM/ZPL equality all pass.
- Actual local runtime: macOS 27.0 (26A428), arm64, Xcode 27.0, Swift 6.4.
- Installed coordinator, virtual queue/maintenance serialization, USB and
  physical printer delivery: NOT RUN. No queue, device or privileged mutation.

## Boundary and next action

These checks protect acquisition against unsafe POSIX owner/mode metadata
and observed namespace replacement. ACLs and production filesystem policy are
not audited by this slice. They do not defend against the trusted effective user deliberately
unlinking a held lock, replacing the namespace later, or privileged filesystem
mutation. The production coordinator must protect its named root/lock throughout
actual readiness/delivery. No claim is made that this constructor makes an
arbitrarily mutable directory a stable ownership domain.

Complete required gates and let hosted run 35200866409 at preceding 8c041aa
finish before publishing the follow-on. PR #81 cloud review is clean only at
base 77c29ff/head a370e05; local inspection of this source is not a new independent
verdict. No third review request, merge or release. Frozen B candidate unchanged.

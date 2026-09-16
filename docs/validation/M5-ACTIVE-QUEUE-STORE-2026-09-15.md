# M5 active queue store evidence — 2026-09-15

## Scope

Commit `aa11db9` adds private mutable persistence for the active immutable
virtual-queue revision. This is local configuration-store evidence only. It
does not create, update, or remove a CUPS destination; change a default printer;
run an administrator path; submit a job; or communicate with printer hardware.

Publication resolves the exact immutable queue/profile/workflow references
before mutation, then takes a per-queue descriptor-relative `flock`. Under that
cross-process exclusion boundary it compares the complete expected selection,
increments the generation, records the prior queue digest, writes bounded
canonical bytes to an owner-only exclusive temporary file, synchronizes the
file, atomically replaces the active pointer, and synchronizes the directory.
A directory-sync failure after rename is reported as `commitUncertain`, not as
a safe pre-commit failure that a caller could blindly retry.

Loads and updates reject stale expectations, fabricated queue digests,
malformed or tampered selection bytes, invalid transitions, unsafe directories,
nonregular files, links, and references that no longer resolve exactly. Queue
identifiers are validated and hashed for on-disk names. Immutable queue files
remain separate, so a held job can retain its prior exact queue reference while
the active pointer advances.

## Validation performed

On Apple Silicon macOS 26.6.2 with Xcode 26.6:

- Active/immutable queue-store focused tests — 9 passed.
- Concurrent stale-expected writers — exactly one replacement succeeded and
  the stored canonical selection matched that winner.
- Fabricated digest and tampered-byte regressions — rejected without activating
  an unverified revision.
- `bash scripts/ci-swift.sh` — PASS.
- Repository preflight and fixture integrity — PASS.
- Python tests — 56 passed.
- LabelCore debug and release — 145 passed in each configuration.
- LabelMac debug and release — 87 passed in each configuration.
- Independent ZPL/PBM/analytic round trips — 132 passed.
- Inert CUPS backend ABI — 15 passed.
- Inert CUPS filter ABI — 10 passed.
- Inert filter-to-discard pipeline — 1 passed.
- Local ad-hoc command-line and setup-app signature checks — PASS; unavailable
  Developer-ID selection continued to fail closed.

## Acceptance impact and remaining gates

This adds partial automated support for M5-AC05 and M5-AC07. Neither row is
complete. The store has not yet been connected to scheduler publication,
held-job capture, UI defaults, repair, update/uninstall, or restart recovery.
Preservation of unrelated queues and system defaults still requires real Tahoe
integration evidence. Administrator, USB, and physical-output gates remain
open.

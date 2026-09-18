# M5 immutable printer-profile store evidence — 2026-09-15

## Scope

Commit `3fc7e58` adds private immutable printer-profile storage and makes it the
trusted resolver for virtual-queue printer bindings. This is local
configuration-storage evidence only. It did not discover or contact a printer,
publish a CUPS queue, mutate a system default, or run an administrator path.

The store canonicalizes a typed profile with `PrinterProfileJSON`, computes its
SHA-256 digest, and returns the only reference accepted by the queue store.
Profiles and queue intents share a descriptor-relative owner-only storage
primitive with bounded no-follow regular-file reads, metadata stability checks,
complete writes, file/directory `fsync`, and exclusive atomic rename. Identical
publication is idempotent; different bytes for one ID/revision conflict.

Queue loading performs a bounded first pass over the same queue bytes to obtain
the printer reference, resolves that exact canonical profile from the private
store, then performs the complete queue decode and revalidates both the exact
printer profile and separately qualified workflow reference. The earlier
caller-supplied printer digest is removed.

## Validation performed

On Apple Silicon macOS 26.6.2 with Xcode 26.6:

- Focused printer-profile and virtual-queue store tests — 9 passed.
- `swift test --package-path Packages/LabelCore` — 141 passed.
- `swift test --package-path Packages/LabelMac` — 83 passed.
- `bash scripts/ci-swift.sh` — PASS.
- Repository preflight and fixture integrity — PASS.
- Python tests — 56 passed.
- LabelCore debug and release — 141 passed in each configuration.
- LabelMac debug and release — 83 passed in each configuration.
- Independent ZPL/PBM/analytic round trips — 132 passed.
- Inert CUPS backend ABI — 15 passed.
- Inert CUPS filter ABI — 10 passed.
- Inert filter-to-discard pipeline — 1 passed.
- Local ad-hoc command-line and setup-app signature checks — PASS; unavailable
  Developer-ID selection continued to fail closed.

Focused cases cover canonical reference creation, exact load, idempotent save,
wrong digest, malformed/tampered bytes, invalid selectors, unsafe roots,
immutable conflicts, and concurrent conflicting writers. Queue tests confirm
the trusted store is required on both save and load.

## Acceptance impact and remaining gates

This adds partial automated support for M3-AC01, M3-AC13, M5-AC05, and M5-AC07.
No row is newly complete. Installed discovery and observation, active queue
revision selection, scheduler publication, update/rollback and held-job policy,
restart recovery, unrelated printer/default preservation, system-dialog option
propagation, USB delivery, and physical acceptance remain open.

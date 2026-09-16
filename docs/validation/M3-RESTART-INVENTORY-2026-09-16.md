# M3 restart inventory and recovery sweep — 2026-09-16

**Scope:** native automated evidence at `b45f93b`. This connects bounded private
store discovery to the existing lease-aware per-job recovery path. It performs
no scheduler, transport, administrator, or printer operation.

## Proven behavior

- Enumeration uses an independently opened directory stream relative to the
  pinned accepted-jobs capability, not a re-resolved root path. Repeated scans
  do not share the stream offset.
- Final names must be lowercase SHA-256 names and match the fully validated
  ticket identity. Canonical ticket/source/state and exact reference checks are
  retained before a job ID enters the recovery sweep.
- Staging entries require the generated UUID namespace and an owned private
  no-follow directory. Invalid entries and valid staging leftovers are reported
  separately, with no deletion or repair.
- Inventory defaults to at most 4,096 entries, 512 MiB declared source bytes,
  and 512 MiB declared prepared bytes. Source budget is reserved before PDF
  ingestion even when later validation fails. Limit failure prevents a partial
  recovery sweep.
- Prepared reads reject files larger than the lifecycle's exact byte binding
  before allocation, in addition to the existing 64 MiB artifact cap.
- The sweep returns stable ID ordering and independent per-job outcomes. One
  unavailable prepared artifact does not hide another valid job.
- A discovered abandoned transmitting job reaches terminal uncertainty through
  the shared device lease, preserving known accepted bytes without replay.

## Local validation

On macOS 26.6.2 with Xcode 26.6:

- focused resolved-ticket suite — 8 passed;
- focused accepted-job persistence suite — 47 passed;
- complete `bash scripts/ci-swift.sh` — passed:
  - 64 Python tests;
  - 165 LabelCore tests in debug and release;
  - 152 LabelMac tests in debug and release;
  - 132 independent encoder round trips;
  - 15 backend ABI, 10 filter ABI, and one inert pipeline case;
  - local ad-hoc command/setup-app signature verification.

## Limits and next boundary

Both permitted independent code-review passes completed cleanly at `53c6b99`,
with no inline findings and a final positive reaction. No third pass is needed.
Hosted workflow run `35069104708` was manually dispatched at the same exact
head because stacked PR bases do not match the workflow's `main` trigger.
Repository preflight, macOS ARM, and `ci-required` all passed. The hosted log
confirms 64 Python tests, 165 LabelCore and 152 LabelMac tests in debug/release,
132 independent round trips, all ABI/inert-pipeline checks, and ad-hoc command
and setup-app signatures. This is hosted automated evidence, not installed
scheduler, retail-host, or physical-printer acceptance.

The inventory is not an atomic snapshot of concurrent publication. Its byte
budgets cover declared artifacts observed during inventory, not a wall-clock
deadline or an exact total of subsequent repeated recovery reads. Per-job
reads and lifecycle reclassification remain independently bounded. A production
startup sequence must coordinate discovery with live intake and add its worker
deadline/cancellation contract.

This is partial automated M3-AC09/12 evidence only. Installed worker startup,
IPC identity/access, scheduler retry mapping, retention/deletion, actual
process-restart integration, USB, physical output, and device confirmation remain
unverified. Private job IDs in the returned records are not general log output.

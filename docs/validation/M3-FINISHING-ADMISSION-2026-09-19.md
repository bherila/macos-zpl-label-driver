# Typed finishing job admission — 2026-09-19

Partial M3 control/admission software only. No installed queue, scheduler
admission, device I/O, transport, privileged action or physical output.

`ResolvedFinishingJobTicket` is a separate typed admission value for the
finishing role. One validation path serves construction and record loading, so
a stored record cannot enter through weaker checks than an accepted job. It
binds, immutably and together: the finishing queue policy reference, the exact
workflow2/3 and schema8 printer references, the physical-device coordination
domain, the explicitly evidenced native pitch and the canvas rebuilt from it,
the whole mode/schedule selection with its cut boundaries, the complete
expanded output order with its single copy and page-range owner, the original
source digest/size/page count, the offline intake provenance, the effective
resolved controls and the cancellation identity.

`FinishingDeviceBinding` carries the portable device identity and pitch.
Unknown or unevidenced pitch fails; a documented-model source identifier is
bounded; a GC420d profile requires 8 dots/mm on both axes, so nominal integer
203 DPI is rejected rather than substituted. The reference 4x6 face resolves to
813x1219 dots. `FinishingJobTicketJSON` is a distinct `offlineFinishingJobTicket`
kind and schema1 record with an exact field set, typed integers and booleans,
and required canonical re-encoding equality, which rejects duplicate keys and
alternate encodings. `preparationBinding`/`validate(preparation:)` carry the same
accepted context into a later raster preparation and name the first field that
disagrees. Ordinary `VirtualQueueDefinition`, `ResolvedJobTicket`,
`PrinterProfile.resolveControls` and `ZPLControlEncoder` admission is unchanged
and still rejects profile8; the two record namespaces do not interchange in
either direction.

## Environment

Linux x86_64 (`Linux 6.18.44-fc-v37`), Swift 6.1.3, Python 3.11, `libcups2-dev`
installed. Worktree `/home/user/wt-c-admission`, branch
`codex/m3-finishing-admission`, based on `d6f03d7`.

## Commands and exact results

| Command | Result |
|---|---|
| `python3 scripts/check_repo.py` | exit 0 — "Repository preflight passed (links, metadata, milestone files, action pins)." |
| `python3 -m unittest discover -s scripts/tests` | exit 0 — 108 tests, OK (skipped=2) |
| `swift test --package-path Packages/LabelCore` | exit 0 — Executed 325 tests, 0 failures (313 before this slice; 12 new) |
| `swift test --package-path Packages/LabelCore --configuration release` | exit 0 — Executed 325 tests, 0 failures |
| `python3 scripts/run-accelerator-checks.py` | exit 0 — "PASS: offline accelerator suite"; 132 cross-language round-trips, 180 ASCII round-trips, 12 benchmark cases, 15 inert CUPS ABI, 14 filter ABI, 1 discard-pipeline case |
| `git diff --check` | exit 0, no output |

Twelve focused cases cover: every finishing mode; every cut schedule
(`everyLabel`, `endOfJob`, batch with and without remainder) and its exact
boundaries; canonical round trip, preliminary reference extraction and
acceptance-identity read; collated, uncollated and already-expanded copies with
page-range selection and retained non-label accounting; each reference, device
domain, snapshot, pitch, provenance, canvas, stock, selection, schedule,
source, cancellation, intake and control substitution failing closed with its
own typed error; both role boundaries; preparation mismatch per field;
duplicate keys, trailing bytes, oversize input, boolean-for-number and exact
large-integer identity.

## Deliberate faults

Each guard was removed individually, the focused suite was run, and the exact
source bytes were restored afterwards.

| Removed guard | Result |
|---|---|
| Canvas equality against the rebuilt device geometry | 1 focused case failed |
| Finishing-role printer schema8 check | 1 focused case failed (`invalidPrinterReference` instead of `ordinaryRoleRejected(7)`) |
| Canonical re-encoding equality in the record codec | 1 focused case failed |

Restored source SHA256:
`ddeaad2ff56dbf323ebb4625c157a890a19cc37b25d55c1dbffa59bb1366820c`
(`FinishingJobTicket.swift`),
`389d8b7683b82f7ba67610eae577afc4c4705f30041f73696e7a983e9937106b`
(`FinishingJobTicketJSON.swift`),
`039bb095f2bb8c556948f3e3d4a59967ae48015cea3f495e079eab2f3003d31c`
(`FinishingJobTicketTests.swift`). All 325 Core tests passed again after
restoration.

Implementation source checkpoint c7a49096cfa8edd07f2d4af772c55ea495c2d18f;
source publication and hosted coverage remain pending.

## Not run, and why

- `swift test --package-path Packages/LabelMac` — NOT RUN. The package declares
  `platforms: [.macOS("26.0")]` and imports CryptoKit, Darwin and CoreGraphics;
  it cannot build on this Linux host. No Linux shim was added and the platform
  declaration was not weakened. No LabelMac source was modified by this slice,
  and no existing public LabelCore signature changed, but LabelMac remains
  uncompiled here and must be built on hosted macOS.
- `bash scripts/ci-swift.sh` — NOT RUN. It requires macOS and `xcrun`.
- Hosted CI, macOS integration, GUI, installation, signing and any hardware
  run — NOT RUN. No printer, scheduler, administrator or network action was
  taken.
- No evidence level is claimed here. This entry records executed Linux
  automation only; it is not an I, H or R result and closes no acceptance ID.

## Limitations

- Construction and loading validate references by identity, revision and
  complete snapshot equality. Canonical reference-digest verification over the
  stored profile/workflow/queue bytes remains the store's responsibility, as it
  already is for `FinishingQueueDefinition`; this layer has no hashing.
- The record binds the integer canvas geometry and the native-pitch provenance.
  The pitch value itself, like the workflow and printer snapshots, is
  independently supplied immutable context at load time.
- The declared source byte count is bounded and carried into the preparation
  binding; it is not verified against document bytes at this layer.
- Re-resolution rejects unqualified, inconsistent or dropped controls. A stored
  control that is itself a qualified explicit job choice re-resolves as that
  explicit choice, exactly as in the ordinary resolved ticket; stored-record
  integrity is the store's digest, not this re-resolution.
- Nothing here persists a record, binds an accepted device, correlates hardware
  status, flattens finishing output into transport bytes or authorizes replay.
  Durable finishing ticket/source publication, identity-bound framing, attempt
  intent and cancellation/lifecycle recovery remain open, as do M1 scheduler and
  privileged-identity evidence and all physical qualification.

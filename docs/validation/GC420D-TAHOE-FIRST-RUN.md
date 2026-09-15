# First-run validation — GC420d USB on Tahoe

**Plan only; no actions or label budget have been approved or executed.** Owner: maintainer. Use exact source SHA and profile revision in each result. Read [baseline](../SPRINT-BASELINE.md), [hardware](../hardware/GC420D.md) and [local signing](../LOCAL-SIGNING.md).

## Phase A — no device commands, no installation

Run repository preflight/portable tests. On the actual Mac, run `bash scripts/host-preflight.sh` and `bash scripts/ci-swift.sh` once M0 prerequisites exist. Record OS patch/build, architecture, compiler/SDK and local-signing smoke output. Keep raw local reports in `local-private/`; public evidence should omit host/user names and device identifiers.

Use user-supplied current queue settings or a separately approved host-only queue inventory to locate the original GC420d queue. Do not read proprietary PPDs/installer files as a discovery shortcut. Do not list all queued job titles or capture customer documents. No assumption is made about the existing queue name, USB URI, VID/PID or printer serial.

## Phase B — M1 capture/installation proof, still no physical printing

With explicit queue/installation approval, install a distinctly named **inert** capture queue and locally signed executable. Save ownership records so rollback touches only experiment-owned items. Check system-dialog options and full source input from Preview, Safari, Chrome and Firefox. Test native 4×6, Letter and A4 separately; extraction workflows must preserve corner markers and complete input sheets.

Prove local ad-hoc code execution under the real spooler identity after UI exit and a planned restart. Verify the proposed native installer/helper authorization path without a Developer ID or Team ID. Record any per-app/helper OS approvals. Do not claim a user-shell `cupsfilter` execution or `codesign --verify` proves scheduler admission. Retain exact MIME/geometry/option observations and teardown evidence.

## Phase C — establish device/media facts before changing them

With explicit permission for named read-only device queries, observe supported identity/status/configuration paths. Host inventory is not a printer query. A configuration-label command consumes stock and needs a separate label allowance. No automatic calibration, reset, firmware change, permanent save, stored-image erasure or maximum-darkness sweep.

Confirm face size versus liner width, gap/mark/notch mechanism, actual label pitch, active speed/darkness and current origin/width. Unknown responses remain unknown; a timeout is not zero. Preserve the working settings until there is a deliberate validated job/profile choice. Record direct thermal and tear-off; reject cutter/peeler/ribbon commands. Do not assume a scanner exists: software decoding of bitmap/photo output is not a substitute for a physical scan claim.

## Phase D — proposed first smoke budget: at most 3 labels

Obtain explicit consent naming GC420d, USB, the intended queue, the exact synthetic files/settings and **three labels maximum**, including retries. Additional queries/feed operations need their own finite budget. Stop on a fault; never spend the remaining allowance on blind retries.

| Label | Job | Oracle |
|---|---|---|
| 1 | Minimal synthetic raw-ZPL baseline via the existing known-working raw path | Confirms unchanged transport; visible sequence ID and orientation; counted against the same budget |
| 2 | Project-rendered native 4×6 synthetic label via the experimental product queue | Final packed bitmap inspected first; four edge markers, spacing ruler, text and synthetic barcode payload; compare physical output |
| 3 | One approved Letter-sheet extraction from a normal application | Correct crop/rotation/scale, one output label, no sheet-sized shrink-to-fit or extra feeds |

The baseline raw submission is an **external developer test only**; production filters/backends must never call `lpr` recursively. To compare fairly, capture explicit settings or document `leave unchanged`; do not alternate independently changing queues during the same job. Preserve the original queue but prevent competing submissions during the approved session. A4 extraction and other browsers come next under a new agreed budget.

Geometry expectations use 8 dots/mm and the chosen rounded canvas, **not** a promise of edge-to-edge printability on unmeasured media. Record actual offsets/tolerances. Require expected barcode data from a real scan when reporting scan success; record unavailable scanner evidence as blocked.

## Phase E — later finite qualification campaigns

After the smoke passes, agree separate budgets for native and Letter/A4 workflows in all required apps; full-page/no-match cases; multipage copies/collation and virtual-queue ordering; gap registration across successive labels; safe speed/darkness comparisons; head-open/media-out; unplug/replug and ambiguous delivery; sleep/wake, app close, reboot; and installation/update/uninstall.

No cutter, peel-wait or ribbon-out campaign belongs on this installed GC420d baseline. Test rejection in software and reserve real accessory/transfer behavior for appropriate hardware. Raw TCP is tested through loopback until another physical target is available, not by inventing an IP address for this USB unit.

Do not deliberately cut power/open the head mid-print without a separate safety-reviewed procedure. Plan failure tests to avoid head/platen damage and uncontrolled label consumption. Record scheduler retry actions as well as backend exits; a second automatic submission is a failure if delivery was uncertain.

## Evidence and clean-environment limitations

Record expected/actual label counts, order, scan payload match (not private payload), measurements, settings, source/profile hashes, code SHA, versions, fault state and remaining stock budget. Keep sanitized evidence using [template](EVIDENCE-TEMPLATE.md).

A fresh login account does not remove machine-wide queues/helpers/approvals. Record whether a test was a reused host, fresh account, disposable Tahoe VM without physical USB, or clean physical host. Do not claim clean-host or M1-machine compatibility from the wrong environment. Only promote the exact observed scope in [compatibility](../COMPATIBILITY.md) and [scope status](../SCOPE-STATUS.json).

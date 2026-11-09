# Decisions and remaining observations

**Revision 2 — 2026-09-15.** The maintainer confirmed the following baseline in this conversation. These decisions supersede the initial handoff's macOS 13, unknown-hardware and pending-license assumptions. They are requirements and user reports, not evidence of a working driver.

| ID | Decision | Status / gate |
|---|---|---|
| D01 | Public OSS repository `bherila/macos-zpl-label-driver` | User-requested target; M0 still verifies access and safe creation/reconciliation |
| D02 | MIT for new project code | Confirmed; no further license question required |
| D03 | Swift-first; Swift 6 language baseline; Core Graphics renderer | Confirmed product direction; keep portable core independent of Apple APIs |
| D04 | macOS Tahoe **26.0 minimum** | Confirmed; no macOS 13/14/15 compatibility work; qualify exact observed 26.x runtimes |
| D05 | Apple Silicon primary | ARM-native required; exact local chip not reported; Intel optional and unqualified |
| D06 | ZPL first | Existing raw ZPL delivery reportedly works; do not substitute EPL as an implicit fallback |
| D07 | First physical target: **Zebra GC420d over USB** | Confirmed model/connection; network adapter remains generic product work, not this hardware baseline |
| D08 | **4 × 6-inch pre-cut stock; tear-off; no cutter** | Confirmed; gap tracking is a setup hypothesis, not an observed gap measurement |
| D09 | CUPS/PPD proof first; independent IPP fallback evaluation | Still an architectural hypothesis; M1 must prove it on Tahoe with local signing |
| D10 | Local-only operation; no account, cloud renderer, telemetry or LLM printing | Required default |
| D11 | No Apple Developer account; **local ad-hoc signing** is the default implementation of local signing | No certificate/Team ID/provisioning requirement; optional local certificate only by later decision |
| D12 | Native UI plus narrowly authorized installation; no privileged renderer | Must work without Developer ID; privilege and trust design still needs runtime proof |
| D13 | Standard hosted `macos-26` ARM CI; Linux ARM for inexpensive preflight | Free public standard-runner tier; no paid/larger capacity; optional `macos-26-intel` only |
| D14 | GC420d-local qualification is a separate release scope from full accessory/model parity | Do not block useful GC420d development on unavailable cutter hardware; do not mark accessory tests passed |

## Known versus still to observe

Known: model, USB, nominal label size, pre-cut form, tear-off, no cutter, OS major/minimum, license, and lack of Developer ID. Do not ask the maintainer to reconfirm them.

Observe locally at the relevant gate: exact OS patch/build and CPU architecture; existing queue name and USB identity; printer firmware; current speed/darkness/origin/width; label face versus liner width and pitch; gap/notch/mark sensing. Do not assume a modern Link-OS/SGD API exists on this model. Device queries, configuration-label printing and test labels require the applicable explicit hardware permission.

The manufacturer documents 8 dots/mm (nominal 203 DPI), direct-thermal printing and programmable speeds 2/3/4 ips. Those are model reference facts, not values measured on this unit. See [GC420D.md](hardware/GC420D.md), [reference-target.json](reference-target.json) and their primary references.

Peeler installation was not separately reported. The selected tear-off setup must not enable peel behavior. Cutter absence is confirmed; thermal-transfer mode is not supported by GC420d. Preserve those distinctions in data.

## Remaining nonblocking inputs

Representative failing PDFs/browser workflows are still useful, but synthetic native/Letter/A4 fixtures are sufficient to start. Real labels remain private unless cleared at source. Bundle namespace `com.bherila.labelprinterdriver` remains a proposed project identifier, not an Apple Team ID.

M0 and safe engine work can begin now. Installation, queue changes and hardware commands still need bounded operational consent; providing a printer model is not authorization to consume labels or mutate system queues. Signing is no longer a missing-credential blocker for the active local scope.

See [sprint baseline](SPRINT-BASELINE.md), [local signing](LOCAL-SIGNING.md), [release scopes](RELEASE-SCOPES.md) and [ADR 0002](adr/0002-reference-and-local-distribution.md).

## Revision 5 — 2026-11-09: installation, coordination and ledger

The maintainer answered these in conversation on 2026-11-09. They are design decisions, not evidence that
anything works; each names what still has to be shown.

| ID | Decision | Status / gate |
|---|---|---|
| D15 | Hosted `macos-26` runners may run `sudo lpadmin` on their own throwaway VM, against a file or discard backend only, never a printer | **Spike first**: a manual-dispatch workflow records runner facts (SIP state, `cupsd`, `sudo`, whether a file-backend queue can be created and deleted) before any per-PR use. A hosted VM is a new, separately declared surface in `docs/test-surfaces.json`, not a relabelled "test Mac". **Spike run 2026-11-09: SIP is disabled on the runner, so `M1-AC01` cannot pass there** ([record](validation/M1-HOSTED-QUEUE-SPIKE-2026-11-09.md)) |
| D16 | Privileged installation is an **unsigned `.pkg`** run by Installer.app, which owns the admin prompt; the app never collects credentials | Feasibility without Developer ID still to be proven in M1 (#129); Gatekeeper first-open friction is documented, never bypassed |
| D17 | Delivery reuses the built-in **`usb://` backend**; the product ships a filter, placed under `/Library/Printers/` | **Provisional.** In CUPS the filter can exit while the backend is still writing, so a filter-held lock does not by itself cover actual device delivery as `AGENTS.md` requires. **Spike run 2026-11-09: backend delivery outlived the filter by 4 s in 3 of 3 runs**, so a filter-held lock does not cover delivery and D17 cannot stand as written; awaiting a maintainer decision ([record](validation/M1-HOSTED-QUEUE-SPIKE-2026-11-09.md)) |
| D18 | The single physical-device and installation coordination domain is **one lock file held with `flock(2)`** in a protected root-owned directory, across the whole interval, by every product queue's job path and every install, uninstall and maintenance action | Answers the held-claim gap in #162 for cooperating processes; kernel releases it on crash. Does not stop uncooperative writers, which stays a recorded residual. ADR 0005 to be updated accordingly |
| D19 | **Clean uninstall is a requirement**, not a convenience: run from the setup app through the standard macOS admin prompt (Authorization Services), removing only what the install receipt recorded | See the uninstall requirements below |
| D20 | `schemaVersion` must change for new **fields**, not for new enum cases | Closed enumerations already make older readers fail closed on an unknown case. Closes #146 with #145's reasoning recorded |
| D21 | The eleven checked rows without a ledger record (#130) are resolved **per row**: record where executed evidence exists at the prescribed level, uncheck otherwise | `M2-AC12` (level I, named reference Mac) is expected to be unchecked. Unchecking withdraws a claim; the criterion is unchanged |
| D22 | `.offlineCandidate` stock admission (#101) gets an **agent security review** | Recorded as an agent review, not a human one |

### Uninstall requirements (D19)

- Removes exactly the queues, filter, PPD, lock directory, support files and package receipt
  (`pkgutil --forget`) that the install recorded, and nothing else: other queues, the system default
  printer and global CUPS settings are left byte-for-byte unchanged.
- Takes the D18 lock first, so it cannot tear files out from under a job in flight; refuses, and says
  why, while a job is held or printing rather than cancelling it silently.
- Works when the app has already been deleted: the same uninstaller is installed alongside the filter
  and is runnable on its own.
- Idempotent and recoverable: an interrupted uninstall rerun completes, and a partial install is
  removable.
- **Verified by a before/after snapshot**, not by the uninstaller's own exit status: the installed file
  set, `lpstat -v`/`lpstat -d` and `pkgutil --pkgs` after uninstall must equal the baseline taken before
  install. This is a hosted-spike test (D15) first, then a test-Mac check.
- **Spike run 2026-11-09:** after cupsd's lazy rewrite (about 28 s), the only residue was scheduler
  bookkeeping (`NextPrinterId` in `printers.conf`) and cupsd's `printers.conf.O` backup, which keeps
  the removed queue's whole definition, `DeviceURI` included. "Equal to the baseline" needs a stated
  allowance for the first and a maintainer decision on the second
  ([record](validation/M1-HOSTED-QUEUE-SPIKE-2026-11-09.md)).

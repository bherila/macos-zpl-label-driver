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

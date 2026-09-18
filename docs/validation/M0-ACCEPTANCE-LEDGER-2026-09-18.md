# Acceptance ledger reconciliation — 2026-09-18

Source: `main` at `56fdc7b13fecdbbd6be3daf505d9c180cf4be136`. Anchor evidence: hosted CI run
35319736124 (job 105519505160, `macos-26` arm64, Swift 6.3.3) — LabelCore 282 tests / 0 failures,
LabelMac 334 tests / 0 failures, `minos 26.0`, `Signature=adhoc`, `TeamIdentifier=not set`,
"No printer accessed". Linux preflight: `check_repo.py` pass, 105 Python tests pass.

No printer, installation, scheduler, GUI or release acceptance is claimed or inferred here.

## Evidence classes

The repository levels (`A`/`C`/`I`/`H`/`R`) are kept verbatim. The 39 `I` criteria are subdivided by
the session each actually requires, because that — not the level — decides what can proceed today.

| Class | Level | Count | Executable where |
|---|---|---:|---|
| automated | A | 30 | Linux and hosted macOS CI |
| config | C | 8 | repository/CI inspection |
| macos-native | I | 12 | hosted `macos-26` CI (noninteractive) |
| gui | I | 10 | test Mac, interactive session |
| installed | I | 17 | test Mac, installed scheduler/helper |
| physical | H | 10 | named GC420d — **unavailable** |
| release | R | 3 | release gate — **not started** |

**50 of 90** criteria are reachable without the printer or an interactive Mac session; **27** wait on the test Mac; **10** on the GC420d; **3** on the release gate.

## Per-criterion ledger

| ID | Class | Level | Area | Status |
|---|---|---|---|---|
| M0-AC01 | config | C | Repository handling | open |
| M0-AC02 | config | C | License and privacy | open |
| M0-AC03 | automated | A | Portable package | coverage verified; ready to record |
| M0-AC04 | macos-native | I | macOS package | coverage verified; ready to record |
| M0-AC05 | config | C | CI execution | open |
| M0-AC06 | config | C | CI fails closed | open |
| M0-AC07 | automated | A | Dependency security | coverage verified; ready to record |
| M0-AC08 | automated | A | Docs and handoff | coverage verified; ready to record |
| M0-AC09 | config | C | Contributor access | open |
| M0-AC10 | config | C | Reporting status | open |
| M0-AC11 | automated | A | Confirmed baseline | coverage verified; ready to record |
| M0-AC12 | macos-native | I | Account-free signing smoke | coverage verified; ready to record |
| M1-AC01 | installed | I | Native scheduler execution | not-run (needs test Mac) |
| M1-AC02 | gui | I | Full-page preservation | not-run (needs test Mac) |
| M1-AC03 | gui | I | Input fidelity inventory | not-run (needs test Mac) |
| M1-AC04 | gui | I | Print-dialog options | not-run (needs test Mac) |
| M1-AC05 | gui | I | Browser distinction | not-run (needs test Mac) |
| M1-AC06 | installed | I | Transform ownership | not-run (needs test Mac) |
| M1-AC07 | installed | I | Profile snapshot | not-run (needs test Mac) |
| M1-AC08 | installed | I | Sandbox and privacy | not-run (needs test Mac) |
| M1-AC09 | macos-native | I | Cancellation and errors | open |
| M1-AC10 | installed | I | Transport ownership | not-run (needs test Mac) |
| M1-AC11 | installed | I | Reversible experiment | not-run (needs test Mac) |
| M1-AC12 | config | C | Decision evidence | open |
| M1-AC13 | installed | I | Local-signing feasibility | not-run (needs test Mac) |
| M2-AC01 | automated | A | Geometry | declared complete; no current evidence record |
| M2-AC02 | automated | A | Original-source rendering | declared complete; no current evidence record |
| M2-AC03 | macos-native | I | PDF semantics | open |
| M2-AC04 | automated | A | One-bit layout | declared complete; no current evidence record |
| M2-AC05 | automated | A | Exact preview | declared complete; no current evidence record |
| M2-AC06 | automated | A | Graphics limits | declared complete; no current evidence record |
| M2-AC07 | automated | A | Compression | coverage verified; ready to record |
| M2-AC08 | automated | A | Copies and output order | coverage verified; ready to record |
| M2-AC09 | automated | A | Resource safety | declared complete; no current evidence record |
| M2-AC10 | macos-native | I | CLI/filter contracts | open |
| M2-AC11 | physical | H | Physical image quality | not-run (GC420d unavailable) |
| M2-AC12 | macos-native | I | Performance baseline | declared complete; no current evidence record |
| M2-AC13 | automated | A | GC420d dot-pitch oracle | declared complete; no current evidence record |
| M3-AC01 | automated | A | Capability truthfulness | declared complete; no current evidence record |
| M3-AC02 | automated | A | Settings validation | declared complete; no current evidence record |
| M3-AC03 | automated | A | Control coverage | coverage verified; ready to record |
| M3-AC04 | automated | A | No implicit persistent mutation | declared complete; no current evidence record |
| M3-AC05 | automated | A | Network correctness | coverage verified; ready to record |
| M3-AC06 | physical | H | USB path | not-run (GC420d unavailable) |
| M3-AC07 | installed | I | Cross-process serialization | not-run (needs test Mac) |
| M3-AC08 | installed | I | Crash/alias handling | not-run (needs test Mac) |
| M3-AC09 | installed | I | Uncertain delivery | not-run (needs test Mac) |
| M3-AC10 | physical | H | Finishing behavior | not-run (GC420d unavailable) |
| M3-AC11 | physical | H | State isolation | not-run (GC420d unavailable) |
| M3-AC12 | automated | A | Privacy and permissions | open |
| M3-AC13 | automated | A | Installed GC420d constraints | declared complete; no current evidence record |
| M4-AC01 | automated | A | Separate media concepts | coverage verified; ready to record |
| M4-AC02 | automated | A | Extraction geometry | declared complete; no current evidence record |
| M4-AC03 | automated | A | Multiple labels/order | declared complete; no current evidence record |
| M4-AC04 | automated | A | Template mismatch | declared complete; no current evidence record |
| M4-AC05 | automated | A | Non-label pages | declared complete; no current evidence record |
| M4-AC06 | gui | I | Teach-once UI | not-run (needs test Mac) |
| M4-AC07 | automated | A | Exact source/preview | declared complete; no current evidence record |
| M4-AC08 | automated | A | Import safety | declared complete; no current evidence record |
| M4-AC09 | macos-native | I | Local assistance | open |
| M4-AC10 | gui | I | Queue workflow | not-run (needs test Mac) |
| M4-AC11 | physical | H | Physical workflow | not-run (GC420d unavailable) |
| M4-AC12 | installed | I | Recovery/snapshots | not-run (needs test Mac) |
| M4-AC13 | automated | A | Three reference workflows | declared complete; no current evidence record |
| M5-AC01 | gui | I | Install-once UX | not-run (needs test Mac) |
| M5-AC02 | macos-native | I | Native architecture | open |
| M5-AC03 | installed | I | Routine application printing | not-run (needs test Mac) |
| M5-AC04 | gui | I | Complete controls/defaults | not-run (needs test Mac) |
| M5-AC05 | installed | I | Virtual queues | not-run (needs test Mac) |
| M5-AC06 | installed | I | Privileged boundary | not-run (needs test Mac) |
| M5-AC07 | installed | I | Transactional lifecycle | not-run (needs test Mac) |
| M5-AC08 | installed | I | Uninstall | not-run (needs test Mac) |
| M5-AC09 | macos-native | I | Diagnostics/privacy | open |
| M5-AC10 | gui | I | Accessibility | not-run (needs test Mac) |
| M5-AC11 | release | R | Local distribution security | not-run (release gate) |
| M5-AC12 | automated | A | Signing-mode separation | declared complete; no current evidence record |
| M5-AC13 | installed | I | Ad-hoc update identity | not-run (needs test Mac) |
| M6-AC01 | automated | A | Traceability | open |
| M6-AC02 | macos-native | I | Runtime support | open |
| M6-AC03 | gui | I | Application support | not-run (needs test Mac) |
| M6-AC04 | physical | H | Device support | not-run (GC420d unavailable) |
| M6-AC05 | physical | H | Barcode/geometry quality | not-run (GC420d unavailable) |
| M6-AC06 | physical | H | Finishing qualification | not-run (GC420d unavailable) |
| M6-AC07 | physical | H | Fault/retry behavior | not-run (GC420d unavailable) |
| M6-AC08 | physical | H | Concurrent workflows | not-run (GC420d unavailable) |
| M6-AC09 | macos-native | I | Performance | open |
| M6-AC10 | release | R | Security/lifecycle gate | not-run (release gate) |
| M6-AC11 | macos-native | I | Optional integration claims | open |
| M6-AC12 | release | R | Release honesty | not-run (release gate) |
| M6-AC13 | config | C | Scoped GC420d closure | open |

## Status summary

- 27 — not-run (needs test Mac)
- 20 — declared complete; no current evidence record
- 19 — open
- 11 — coverage verified; ready to record
- 10 — not-run (GC420d unavailable)
- 3 — not-run (release gate)


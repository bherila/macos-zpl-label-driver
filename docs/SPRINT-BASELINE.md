# Sprint baseline — GC420d / USB / Tahoe / local signing

**Normative revision 2, 2026-09-15.** Read this before M0. The six product milestones and 38 review-sized slices remain; this revision specifies the first real configuration rather than starting a second project.

## First qualification target

| Dimension | Baseline |
|---|---|
| Printer | Zebra GC420d; direct thermal; ZPL |
| Connection | USB, using discovered identity; no guessed device URI or VID/PID |
| Loaded media | Nominal 4 × 6-inch pre-cut labels; tear-off; no cutter |
| Sensing | Preserve verified current configuration first; propose gap/web only after setup confirmation |
| Geometry | Documented pitch 8 dots/mm; use physical geometry, not an exact integer 203-DPI shortcut |
| Mac | macOS Tahoe 26.0 minimum, Apple Silicon first; record actual minor/build/chip |
| License | MIT confirmed for original code |
| Signing | Local ad-hoc; no Developer ID, provisioning profile, notarization or paid account required |
| Trust claim | Local/source-built software; not Apple-verified or notarized public distribution |
| Qualification | Initially unqualified; existing raw success belongs to the preexisting queue, not this project |

See [hardware reference](hardware/GC420D.md) for sourced model facts and [reference-target.json](reference-target.json) for machine-readable planning inputs. The JSON is not a runtime capability-profile format and must not be loaded directly into production before M3 schema review.

## What changes in execution

1. **M0:** import MIT, set Mac deployment targets to 26.0, use `macos-26`, run secret-free local-signing smoke, record host facts. Do not implement compatibility shims for older macOS.
2. **M1:** prove actual system-dialog capture/options and installed spooler execution on Tahoe using the same local-signing mode that will ship locally. Add an early installation/authorization feasibility spike; do not discover in M5 that the chosen helper relies on a missing Team ID.
3. **M2/M3:** implement GC420d geometry and USB path first; validate tear-off/direct-thermal controls and reject unsupported finishing. Keep generic transport/accessory abstractions and tests without sending accessory commands to this printer.
4. **M4/M5:** qualify native 4×6, Letter extraction and A4 extraction workflows; preserve full input sheets. Source-built local installation, update and uninstall are the active delivery target.
5. **M6:** produce a GC420d-local evidence report. Keep untested accessories, network devices and optional trusted-public distribution explicitly outside that claim, not globally passed or deleted.

These are sequencing priorities, not permission to skip browser extraction, defaults, ordinary printing, correctness or security. [Release scopes](RELEASE-SCOPES.md) distinguish a useful supported baseline from the broader parity backlog.

## Do first, without hardware writes

Read the shared contracts and all M0 files. Run repository preflight and portable tests. On the local Mac run `bash scripts/host-preflight.sh`; it checks host/toolchain versions and scheduler availability without listing printer identities, parsing proprietary drivers or sending a job. A missing Xcode/SDK should produce an explicit setup error.

After a Mac build, `bash scripts/sign-local-diagnostic.sh` signs and executes **only the inert diagnostic**. This is not an installer or proof that the printing system accepts every future helper. Actual M1 capture installation is separately authorized.

## Unattended work boundaries

An agent can implement and run bounded non-hardware tests throughout the sprint. Record GUI/physical checks that are waiting on the maintainer and continue independent code. Do not stop to request an Apple Developer account. Do not globally disable protections, loosen helper authentication or claim tests passed to avoid a wait.

Before any hardware session, obtain a named-device, finite job/label/command budget. The [first-run plan](validation/GC420D-TAHOE-FIRST-RUN.md) proposes a three-label initial smoke test; it is **not** preauthorized by this handoff. Preserve the working queue and avoid competing jobs through it during an explicitly approved project test.

## Success for this sprint's baseline

A locally built and signed ARM-native system on the tested Tahoe host installs reversibly, prints correctly from ordinary apps to the GC420d over USB, handles native and extraction workflows, exposes supported controls/defaults, and does not require its UI window to remain open. Every physical claim has real evidence. Local signing limitations are clear to other OSS users; the full accessory-capable product roadmap stays open.

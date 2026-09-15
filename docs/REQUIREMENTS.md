# Requirements traceability

All requirements remain mandatory for the full functional target. [Release scopes](RELEASE-SCOPES.md) separates the first GC420d-local qualification from broader accessory/model evidence and optional deferred trusted-public binaries. Scope restrictions cannot turn failed tests into passes.

| ID | Product requirement | Acceptance IDs |
|---|---|---|
| F01 | Native Apple Silicon ordinary-application printing | M1-AC01, M5-AC02, M5-AC03, M6-AC02 |
| F02 | Printer controls through the system dialog | M1-AC04, M1-AC05, M5-AC04 |
| F03 | Speed and darkness/heat controls | M3-AC02, M3-AC03, M3-AC11 |
| F04 | Thermal method, media tracking, dimensions and offsets | M3-AC01, M3-AC02, M3-AC03 |
| F05 | Cutter, peeler and qualified finishing modes | M3-AC10, M6-AC06 |
| F06 | Sharp, barcode-readable label imaging and exact preview | M2-AC02, M2-AC03, M2-AC04, M2-AC05, M2-AC11, M6-AC05 |
| F07 | Measured high-speed preparation and printing | M2-AC07, M2-AC12, M6-AC09 |
| F08 | Small-label/browser compatibility via correct input page configuration | M1-AC02, M1-AC03, M4-AC01, M4-AC10, M6-AC03 |
| F09 | Letter/A4 extraction, rotation and scaling | M2-AC01, M4-AC02, M4-AC04, M4-AC11 |
| F10 | Automatic qualified matching and teach-once setup | M4-AC04, M4-AC06, M4-AC09 |
| F11 | Multiple regions/pages and correct copies/order | M1-AC06, M2-AC08, M4-AC03, M4-AC05 |
| F12 | Utility defaults and immutable per-job choices | M1-AC07, M4-AC12, M5-AC04 |
| F13 | Multiple virtual queues sharing one device | M3-AC07, M3-AC08, M5-AC05, M6-AC08 |
| F14 | Guided install, repair, upgrade and uninstall | M5-AC01, M5-AC06, M5-AC07, M5-AC08, M5-AC11 |
| F15 | Privacy, bounded parsing and secure privileged operation | M2-AC09, M3-AC04, M3-AC12, M4-AC08, M5-AC06, M5-AC09 |
| F16 | Correct status, cancellation and uncertain-delivery recovery | M1-AC09, M3-AC05, M3-AC06, M3-AC09, M6-AC07 |
| F17 | Independent OSS implementation and provenance | M0-AC01, M0-AC02, M0-AC07, M6-AC12 |
| F18 | Reproducible project setup and cost-conscious CI | M0-AC03, M0-AC04, M0-AC05, M0-AC06, M0-AC08, M0-AC09, M0-AC10 |
| F19 | Truthful evidence-backed compatibility and distribution | M6-AC01, M6-AC04, M6-AC10, M6-AC11, M6-AC12 |
| F20 | Confirmed GC420d USB/Tahoe physical-pitch baseline and scoped evidence | M0-AC11, M2-AC13, M3-AC13, M4-AC13, M6-AC13 |
| F21 | Account-free local signing and secure local installation/update | M0-AC12, M1-AC13, M5-AC11, M5-AC12, M5-AC13 |

## Scope boundary

Native printing, imaging, extraction, supported controls and safe lifecycle remain required. GC420d USB is the first actual hardware target; generic TCP/accessory/model work remains unqualified until evidence exists. No older macOS or Apple Developer account is required. Global finishing gates remain open when S1 uses tear-off-only hardware.

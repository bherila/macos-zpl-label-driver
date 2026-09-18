# Primary references

**Checked during handoff preparation: 2026-09-15.** These references explain APIs/protocols and CI policy. They are not evidence that the proposed driver works. Specs contain project design choices, which are not attributed to vendors. Revalidate time-sensitive runner/toolchain/security information before release.

No commercial implementation was inspected. Public marketing text supplied by the user defines desired behavior only.

<a id="r01"></a>
## R01 — CUPS filter/backend contract

[CUPS filter/backend contract](https://www.cups.org/doc/api-filter.html)

Arguments, process roles, signals, permissions and macOS sandbox boundaries. Revalidate scheduler behavior on supported macOS versions.

<a id="r02"></a>
## R02 — CUPS PPD extensions

[CUPS PPD extensions](https://www.cups.org/doc/spec-ppd.html)

Filter declarations and PPD option extensions. It documents deprecated custom dialog-extension behavior; not a current-OS promise.

<a id="r03"></a>
## R03 — Apple PPD files tasks — retired documentation

[Apple PPD files tasks — retired documentation](https://developer.apple.com/library/archive/documentation/Printing/Conceptual/UsingPPDFiles/ppd_tasks/ppd_tasks.html)

Historical generic Printer Features behavior. The page explicitly warns it is retired; use as a hypothesis for M1, not proof of modern compatibility.

<a id="r04"></a>
## R04 — CUPS lpadmin manual

[CUPS lpadmin manual](https://www.cups.org/doc/man-lpadmin.html)

Queue/default management and legacy-driver deprecation notice. Does not establish a specific Apple macOS removal date.

<a id="r05"></a>
## R05 — GitHub-hosted runner reference

[GitHub-hosted runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)

Active standard labels are ubuntu-24.04-arm and macos-26 (ARM); macos-26-intel is optional. Recheck labels and architecture when adopting/updating workflows; older macOS is outside this project baseline.

<a id="r06"></a>
## R06 — GitHub Actions billing

[GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)

Standard GitHub-hosted runner use in public repositories is free. Larger runners and storage/other services have separate rules; public OSS is not carte blanche for paid capacity.

<a id="r07"></a>
## R07 — Zebra ^GF graphics command

[Zebra ^GF graphics command](https://docs.zebra.com/us/en/printers/software/zpl-pg/c-zpl-zpl-commands/r-zpl-gf.html)

Graphic format, decoded-byte counts and field bounds. Implement original test vectors and validate actual firmware behavior; do not copy an entire manual.

<a id="r08"></a>
## R08 — Apple Quartz PDF drawing and transforms

[Apple Quartz PDF drawing and transforms](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/drawingwithquartz2d/dq_pdf/dq_pdf.html)

Core Graphics PDF page rendering, boxes and transformations. Additional document semantics and exact deployment availability require implementation tests.

<a id="r09"></a>
## R09 — Swift installation and tooling

[Swift installation and tooling](https://www.swift.org/install/)

Official Swift tooling entry point. The handoff uses a Swift 6 language baseline, not a claim to require the newest compiler.

<a id="r10"></a>
## R10 — Apple Vision barcode detection

[Apple Vision barcode detection](https://developer.apple.com/documentation/vision/detectbarcodesrequest)

Barcode detection capability. The linked request must be tested on the 26.0 minimum/current observed runtime; guard APIs introduced in later releases.

<a id="r11"></a>
## R11 — Zebra ^PR speed

[Zebra ^PR speed](https://docs.zebra.com/us/en/printers/software/zpl-pg/c-zpl-zpl-commands/r-zpl-pr-print-rate.html)

Print/feed/backfeed speed semantics and model limits; speed and stock affect physical quality.

<a id="r12"></a>
## R12 — Zebra ~SD darkness

[Zebra ~SD darkness](https://docs.zebra.com/us/en/printers/software/zpl-pg/c-zpl-zpl-commands/r-zpl-sd.html)

Darkness semantics and command interactions. Do not present software threshold or temperature as the same control.

<a id="r13"></a>
## R13 — PAPPL programming manual

[PAPPL programming manual](https://www.msweet.org/pappl/pappl.html)

Reusable IPP printer-application framework and driver integration. Custom options still require macOS client UI proof.

<a id="r14"></a>
## R14 — Swift on Linux

[Swift on Linux](https://www.swift.org/install/linux/)

Portable Swift tooling and official container distribution. Linux does not provide Apple Core Graphics or native macOS scheduler/GUI validation.

<a id="r15"></a>
## R15 — Apple SMAppService

[Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)

Service lifecycle API to assess for the chosen deployment target. Registration does not remove authorization or privileged-boundary design requirements.

<a id="r16"></a>
## R16 — Apple notarization

[Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

Developer ID distribution and notarization process.

<a id="r17"></a>
## R17 — Apple custom notarization workflow

[Apple custom notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)

Automated notarization workflow reference. Signing credentials are kept outside untrusted PR execution.

<a id="r18"></a>
## R18 — GitHub Actions secure use

[GitHub Actions secure use](https://docs.github.com/en/actions/reference/security/secure-use)

Immutable action references and untrusted workflow input/security considerations.

<a id="r19"></a>
## R19 — Pinned checkout action source

[Pinned checkout action source](https://github.com/actions/checkout/tree/3d3c42e5aac5ba805825da76410c181273ba90b1)

Verified tag v7.0.1 resolves to this commit as of handoff preparation; initial workflow pin. This is a build dependency, not shipped driver code.

<a id="r20"></a>
## R20 — Pinned upload-artifact action source

[Pinned upload-artifact action source](https://github.com/actions/upload-artifact/tree/043fb46d1a93c77aae656e7c1c64a875d1fc6a0a)

Verified tag v7.0.1 resolves to this commit as of handoff preparation; initial workflow pin. Reassess release updates through normal review.

<a id="r21"></a>
## R21 — CUPS cupsfilter manual

[CUPS cupsfilter manual](https://www.cups.org/doc/man-cupsfilter.html)

Diagnostic filter invocation is useful but must not be confused with actual scheduler security/session behavior.

<a id="r22"></a>
## R22 — Zebra ^MM print mode

[Zebra ^MM print mode](https://docs.zebra.com/us/en/printers/software/zpl-pg/c-zpl-zpl-commands/r-zpl-mm.html)

Tear-off, peel and cutter-related modes depend on device/accessories; physical wait/cut behavior requires testing.

<a id="r23"></a>
## R23 — Zebra ^MN media tracking

[Zebra ^MN media tracking](https://docs.zebra.com/us/en/printers/software/zpl-pg/c-zpl-zpl-commands/r-zpl-mn.html)

Continuous/gap/mark tracking options and model restrictions.

<a id="r24"></a>
## R24 — Zebra ^MT thermal method

[Zebra ^MT thermal method](https://docs.zebra.com/us/en/printers/software/zpl-pg/c-zpl-zpl-commands/r-zpl-mt.html)

Thermal-transfer/direct-thermal method selection; installed hardware and stock must be appropriate.

<a id="r25"></a>
## R25 — GitHub runner images

[GitHub runner images](https://github.com/actions/runner-images)

Runner image/toolchain inventory. Log exact image/toolchain per job; an OS label does not freeze its installed Xcode forever.

<a id="r26"></a>
## R26 — Zebra GC420 d/t technical specifications

[Zebra GC420 d/t technical specifications](https://www.zebra.com/content/dam/zebra_new_ia/en-us/solutions-verticals/product/Printers/Desktop%20Printers/G-Series%20GC%20Desktop%20Printers/GENERAL/documents/gc20d-t-tech-specs.pdf)

Official combined-model reference, inspected text and rendered pages 1–2 on 2026-09-15. Dot pitch, dimensions, speed choices, sensing and USB reference. Do not apply the t-model ribbon features to the GC420d; model facts do not qualify the installed unit. Manual is linked, not bundled.

<a id="r27"></a>
## R27 — Zebra GC420d support

[Zebra GC420d support](https://www.zebra.com/us/en/support-downloads/printers/desktop/gc420d.html)

Official direct-thermal model identification and public documentation entry point. No vendor driver package is needed for this project.

<a id="r28"></a>
## R28 — Apple macOS Code Signing In Depth

[Apple TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html)

Code validity, designated requirements and subsystem trust are distinct. Archived technical reference; actual Tahoe helper/Gatekeeper behavior still needs runtime evidence.

<a id="r29"></a>
## R29 — Apple ad-hoc signature flag

[Apple SecCodeSignatureFlags.adhoc](https://developer.apple.com/documentation/security/seccodesignatureflags/adhoc)

Certificate-free ad-hoc code-signature mode; also inspect the target host's `man codesign` for command semantics. Not iOS Ad Hoc provisioning.

<a id="r30"></a>
## R30 — Apple app security and per-app approval

[Safely open apps on your Mac](https://support.apple.com/en-us/102445)

Gatekeeper/developer/notarization policy and user-directed app approval. No guarantee that code verification admits every downloaded app/helper; never disable protections globally.

<a id="r31"></a>
## R31 — GitHub standard macOS 26 runners

[macOS 26 generally available runner labels](https://github.blog/changelog/2026-02-26-macos-26-is-now-generally-available-for-github-hosted-runners/)

Official announcement documents `macos-26` ARM and `macos-26-intel` standard labels. Current support and public-runner billing are checked through R05/R06. No paid larger runner is required.

<a id="r32"></a>
## R32 — Netpbm PBM format

[PBM format specification](https://netpbm.sourceforge.net/doc/pbm.html)

Primary reference for the raw one-bit exact-preview container. The project emits
a narrow canonical P4 form; its test parser is not a general PBM implementation.

<a id="r33"></a>
## R33 — ReportLab generation documentation

[ReportLab documentation](https://docs.reportlab.com/)

Development-only original vector/Code128/QR fixture generation. No ReportLab
implementation or fonts are bundled in the runtime driver.

<a id="r34"></a>
## R34 — CUPS server-bin configuration

[CUPS cups-files.conf manual](https://www.cups.org/doc/man-cups-files.conf.html)

Defines `ServerBin` as the scheduler directory containing backends and filters;
changing it requires a scheduler restart. This documents the CUPS contract, not
a permitted Tahoe installation path or successful local admission.

<a id="r35"></a>
## R35 — Apple read-only I/O Registry matching

[IOServiceGetMatchingServices](https://developer.apple.com/documentation/iokit/1514494-ioservicegetmatchingservices)
and [IORegistryEntryCreateCFProperty](https://developer.apple.com/documentation/iokit/1514293-ioregistryentrycreatecfproperty/).

Public matching/property APIs; the installed SDK's `IOKitLib.h` explicitly
permits successful empty matching with a null iterator. Public USB host class
and matching-property constants are in `usb/IOUSBHostFamilyDefinitions.h`.
Enumeration does not establish stable physical identity, device access, model
qualification, printer status or transmission. No implementation is bundled.

<a id="r36"></a>
## R36 — Apple Vision barcode locations

[VNDetectBarcodesRequest](https://developer.apple.com/documentation/vision/vndetectbarcodesrequest),
[request symbologies](https://developer.apple.com/documentation/vision/vndetectbarcodesrequest/symbologies),
and [Vision coordinate systems, WWDC24](https://developer.apple.com/videos/play/wwdc2024/10163/).

Public system-framework API, revision 3, with an explicitly selected Code128/QR
subset. Vision locations use normalized lower-left coordinates; the project
converts them to its upright top-left geometry. Product code reads locations
and symbology only, never barcode payload values or descriptors. A location is
candidate evidence, not a label boundary, validated barcode or carrier identity.
No independent third-party implementation or model is bundled. API documentation
does not establish network-disabled runtime or physical scanning acceptance.

<a id="r37"></a>
## R37 — Apple user-initiated clipboard writing

[Universal Clipboard](https://support.apple.com/en-gb/102430) describes automatic
sharing with nearby configured devices. App-local behavior does not guarantee
that OS services or clipboard managers keep copied text on one machine.

[NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard/)
and [setString(_:forType:)](https://developer.apple.com/documentation/appkit/nspasteboard/setstring(_:fortype:)).

Public AppKit system-framework APIs used only for an explicit offline diagnostics
copy action. The fixed report contains state flags, not document data, identifiers,
paths or raw exceptions. Copying replaces clipboard contents, which other apps
may read; it is not private storage or an automatic export. No clipboard contents
are read and no third-party implementation is bundled. Documentation and unit
tests do not establish actual GUI/clipboard operation or full diagnostic acceptance.

<a id="r38"></a>
## R38 — Apple loopback listener and native socket fault fixtures

[requiredLocalEndpoint](https://developer.apple.com/documentation/network/nwparameters/requiredlocalendpoint)
selects a specific local endpoint for connections/listeners.
[setsockopt](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/setsockopt.2.html)
documents receive buffering and linger options; it is historical API reference,
not a current-runtime compatibility guarantee.

The native test fixtures bind only to loopback, limit receive buffering and
observe real adapter timeout/reset behavior. They use public system APIs without
bundling a third-party implementation. Current host observations and automated
stream/race tests do not establish printer, scheduler, physical-output or general
network-permission acceptance.

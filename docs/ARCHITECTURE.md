# Architecture

## Objective

One saved workflow controls how the incoming application's document becomes labels and how the physical printer produces them. Preserve the standard macOS Print experience; avoid a routine 'save PDF, then open another app' workflow.

## Component boundaries

```text
Application / system Print dialog
                |
        macOS queue adapter
                |
       immutable resolved job
                |
    preflight + label planning
                |
      Quartz page rendering
                |
   monochrome + exact-bitmap preview
                |
          ZPL encoding
                |
  device-wide delivery coordination
                |
       USB / network adapter
                |
         physical printer
```

The setup app manages device/media/workflow profiles, queue configuration and diagnostics. Installation helper operations are distinct from all document processing. The UI is not required to remain open for printing.

## Modules

| Proposed component | Responsibility | Platform |
|---|---|---|
| `LabelCore` | Checked geometry, profiles, job planning, bitmaps, encoder and state-machine logic | Portable Swift |
| `LabelMac` | Core Graphics, barcode-detection adapter, CUPS interop, supported OS services | macOS |
| `label-driver-filter` (M1/M2) | CUPS ABI ingress, validated job resolution, preparation, printer output | macOS executable |
| Delivery adapter / backend (M1/M3) | Device ownership, transport, status and cancellation | macOS executable/service boundary |
| `LabelPrinterSetup` (M4/M5) | Native setup, extraction editor, defaults, status and diagnostics | SwiftUI/AppKit |
| Narrow installation helper (M5) | Authenticated allowlisted installation/queue actions | macOS privileged boundary |
| Optional IPP adapter (M6) | PAPPL-backed alternative integration after proof | Separate adapter |

These names are proposed target names, not claims that the binaries already exist. The supplied `label-driver-diagnostics` is only a scaffold smoke test.

## Integration gate

M1 must establish actual input MIME types, full-page geometry, option propagation, copy/page-range behavior, sandbox execution and profile availability. `cupsfilter` run in a user shell is not a substitute for an installed queue invoked by the scheduler. Archived Apple PPD documentation suggests generic Printer Features UI; it explicitly is retired and cannot establish current compatibility. Custom Print Dialog Extensions are not the foundation. [R01](REFERENCES.md#r01) [R02](REFERENCES.md#r02) [R03](REFERENCES.md#r03)

Do not require one MIME path by wishful declaration. Capture what Preview, Safari, Chrome and Firefox actually submit. If a path supplies already-rasterized content, record source resolution and whether it meets that workflow's quality requirement. Do not reconstruct lost vector detail by upscaling. If the browser path clips the page before capture, first correct application-facing media, then reassess the adapter.

## Transport and lock ownership

Conversion and transport are distinct. A filter writing ZPL to stdout does not own the physical device until the downstream backend finishes. A lock around conversion alone can release too early. M1 selects a transport ownership model that remains valid in the macOS printing sandbox; M3 implements it.

Prefer reuse of the working transport where its documented contract can be preserved. A product backend may delegate a system USB backend only after testing discovery mode, argument/environment handling, file descriptors, signal forwarding, exit codes, privileges and child lifetime. Do not hardcode an unverified system path. A new USB implementation is an explicit fallback with its own tests, not an assumed requirement for Apple Silicon.

All product-owned virtual queues and maintenance operations must share a stable physical-device identity and serialization mechanism. A backend/coordinator holds ownership until the operation and documented device-readiness boundary finish. Different queue names or connection aliases must not bypass it. Two unrelated hosts or another vendor's queue are outside local locking; document exclusive-use expectations instead of promising global serialization.

## Profile and job lifecycle

Store typed, versioned profiles in a location readable by the actual spooler identity, not the logged-in user's preferences alone. The setup app may edit drafts in its own storage; a validated immutable revision is published for queue use. Do not allow a job option to name an arbitrary filesystem path.

Bind the revision into submitted options where the adapter permits it. The project snapshot point is explicit and evidenced. Changing a profile while a job is held must not cause that job to silently resolve a different profile. Retain old immutable revisions while referenced; garbage-collect after safe reference expiry. If submission-time binding cannot be established, hold affected work and expose the limitation rather than claiming immutability at OS acceptance.

## Input media and output stock

`inputDocumentMedia` describes the document the application produces. `outputLabelStock` describes the loaded physical roll/sheet. Letter input may map to multiple 4x6 labels. Never represent both with one `paperSize` or silently change input layout when changing output stock.

Native-size workflow and sheet-extraction workflow are different queue/profile configurations. System/application preview may show the incoming sheet; the companion preview shows final labels. The product must not promise to replace every application's preview.

## Preparation and partial jobs

Default to validate, plan, render and encode a bounded job before transmitting its first byte. Use quota-controlled private scratch files when necessary; do not require every page bitmap in RAM. This trades some first-label latency for avoiding predictable partial output when a later page is invalid. Oversized jobs fail before delivery, with a useful limit message.

An optional streaming mode requires an ADR documenting partial-output semantics, recovery, cancellation and disclosure. 'Preflight passed' alone does not prove later rendering cannot fail. Physical transmission can still become ambiguous even for a fully prepared job.

## Performance

Render from the original page directly to intended output geometry. Use contiguous buffers and bounded page/band work. Performance is measured on a known Mac, printer, media and connection; Swift versus C++ is not a substitute for measurement. Compression is lossless and capability-gated. Detection thumbnails are not reused for printing.

## Platform strategy

Swift 6 language features must remain compatible with the selected deployment target. Avoid unguarded newer APIs. The minimum Mac runtime is 26.0; no pre-Tahoe compatibility shim is required. Guard any API introduced after 26.0 and test the actual Vision path on the observed runtime. M0/M1 must record compiler, SDK, deployment target and observed runtime versions.

PPD/CUPS deprecation makes the adapter boundary important, but is not proof of a particular macOS removal date. An IPP server is an alternative transport into the same engine, not automatic parity for custom print-dialog controls. [R04](REFERENCES.md#r04) [R13](REFERENCES.md#r13)

## Reference setup and no-account trust boundary

The initial device is GC420d USB with 4×6 pre-cut media and tear-off. Keep capability versus installed-hardware facts separate and use [GC420d geometry](hardware/GC420D.md). Other models/transports remain reusable adapters, not blockers to the first controlled physical path.

All Mac targets deploy to 26.0 or newer by explicit decision. Prove filter/backend and installer admission under **local ad-hoc signing** in M1. A valid ad-hoc signature is not an Apple Team identity or installation authorization. Do not defer this architecture question until packaging. See [local signing](LOCAL-SIGNING.md) and [release scopes](RELEASE-SCOPES.md).

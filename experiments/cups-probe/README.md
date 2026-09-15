# Inert native CUPS probe — M1 starter

This is a **discard-only experiment**, not a printer driver. It is never suitable
for an ordinary printer queue or unattended real shipping work. Success means an
inert sink observed input; it does not mean a document printed.

## What is already implemented

`labelprobe` is a Swift executable in LabelCore. It supports the CUPS positional
job ABI, filename or stdin input, bounded reading, signal termination, a narrow
allowlist of experiment options, signature sniffing, and sanitized JSON on stderr.
It has no device transport, network operation, installation code or payload writer.
Job invocations refuse any destination other than exactly `labelprobe://discard`.
No-argument discovery lists only that explicit discard destination.

`labelcapture-filter` is the matching inert filter-stage executable. It accepts
the positional job ABI, validates the bounded input/options contract, and writes
the exact stream to stdout for the next stage (normally only the `labelprobe`
discard backend). It emits sanitized stderr metadata and never retains a payload,
opens a device, invokes `lpr`, or selects a destination. It is not installed and
has no printer-safe standalone mode.

The source is cross-platform for offline tests; the installed product target
remains Tahoe 26. A Linux ABI test does not validate a Mac spooler.

Build and exercise without privileges or queues:

```sh
swift build --package-path Packages/LabelCore
python3 scripts/check_probe.py Packages/LabelCore/.build/debug/labelprobe
python3 scripts/check_capture_filter.py Packages/LabelCore/.build/debug/labelcapture-filter
```

The checker exercises file/stdin input, option propagation, privacy, bad paths,
symlinks, an oversized sparse file, cancellation and a stalled pipe. No hardware
or root permissions are needed. The 10-second timeout test intentionally takes
approximately that long. Per-job input is capped at 64 MiB.

## Candidate PPDs

The three `.ppd` files are original experimental descriptors. They advertise
native 4x6, Letter and A4 media and selected no-op option tokens. The proposed
pass-through PDF rules and generic Printer Features exposure MUST be proved on
Tahoe. Full-page imageable area belongs to the inert input surface, not the
GC420d's physical printhead or calibrated media.

Do not publish these as GC420d profiles. They include no cutter, thermal transfer,
calibration, or device-control command. The controls record selection only.

## Next Mac experiment — do not install automatically

1. Run the existing host preflight, build natively and locally ad-hoc sign the
   probe. Verify the exact signed binary. No Apple identity is required by design;
   actual admission remains the M1 experiment.
2. Determine and record a **supported writable add-on backend placement and
   permissions on the actual Tahoe host**. Do not guess from old CUPS paths or
   change SIP, global CUPS configuration or the existing Zebra queue. Failure to
   establish a safe placement is an ADR blocker, not permission to bypass security.
3. After explicit installation/queue authorization, install only the inert
   experiment with an ownership/rollback record. Queue names must include
   `DISCARDS JOBS`. Its destination must be `labelprobe://discard` and it must not
   become the default printer. Run `cupstestppd -v` on each candidate where the tool
   is available; repair and record any validation findings.
4. Use only the generated synthetic PDF/HTML inputs. Set non-default token values
   in the **system** dialog and confirm `knownOptions`, `copiesArgument`, MIME
   labels and byte counts in the backend diagnostic. Compare Preview, Safari,
   Chrome and Firefox separately; no installed browser is assumed.
5. Record scheduler account, resolved executable path, shared-library admission,
   state after closing the settings UI, cancellation, and a planned restart.
6. Remove only the owned experiment according to the recorded rollback plan.

No copy/paste privileged installer is supplied because its safe Tahoe placement
and authorization contract are precisely what M1 must establish.

## What this probe does NOT prove

It does not retain or parse the PDF and cannot prove page count, page boxes,
vector fidelity, complete corner-marker capture, crop correctness, digest
identity, collation, interqueue locking, helper security or physical delivery.
A `%PDF-` signature is not proof of a valid PDF. A producer can deliver malformed
PDF, PostScript, raster or unknown bytes and the inert sink will report what it
observed without claiming it rendered them.

M1 must add bounded, opt-in synthetic payload capture and native PDF inspection
for the full fidelity gate. Captured content must stay in a private, owned local
location, not stdout/logs or the repository. Production option parsing must use
the proven CUPS/IPP contract rather than treating `ProbeOptions` as complete.

## References

CUPS documents the ABI and stderr protocol [R01](../../docs/REFERENCES.md#r01),
and PPD conversion declarations [R02](../../docs/REFERENCES.md#r02). See also
[macOS integration milestone](../../docs/milestones/01-printing-integration/SPEC.md).

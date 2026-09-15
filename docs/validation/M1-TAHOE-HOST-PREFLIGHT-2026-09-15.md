# M1 Tahoe host preflight — 2026-09-15

**Scope:** read-only host/scheduler inspection for the approved inert M1
experiment. This is not queue installation, printer I/O, an administrator
authentication attempt, or local-signing admission evidence.

## Observations

| Item | Result |
|---|---|
| Host OS | macOS 26.6.2 (build 25G83), Apple Silicon |
| Toolchain | Xcode 26.6; macOS SDK 26.5; Swift 6.3.3 |
| Scheduler | Running at observation time |
| Existing physical setup | An existing default destination and USB connection were observed but are deliberately not named or identified here. No driver asset, PPD, serial, URI, job title, or device setting was inspected or changed. |
| CUPS server bin | `cups-config --serverbin` reports `/usr/libexec/cups`; the backend and filter directories there are root-owned and non-writable to the current user. |
| `/Library/Printers` | The observed top-level directory is root-owned/non-writable; it contains only the standard visible PPD/icon structure at the inspected depth. No add-on backend/filter contract was established from this observation. |

## Consequence

The current M1 discard-queue experiment must **not** copy an executable into a
system CUPS directory merely because root authentication is available. A
supported Tahoe add-on placement, code-admission behavior, ownership/rollback
record, and narrow OS-authorized installation path remain to be established
before creating `LabelProbe_DISCARDS_JOBS` or installing either inert executable.

No CUPS queue/default was changed, no existing printer was touched, and no
printer data was sent. This host is a reused system with a pre-existing physical
configuration, not a clean-host result.

## Next finite action when placement is resolved

1. Build and locally ad-hoc sign the inert filter/backend artifacts.
2. Use OS-supported administrator authorization only for the reviewed,
   experiment-owned placement and queue transaction.
3. Create only the explicitly named, nondefault, unshared discard queue; run
   synthetic native/Letter/A4 checks; then remove only recorded owned artifacts.

Until then, M1-AC01 through M1-AC13 remain unchecked.

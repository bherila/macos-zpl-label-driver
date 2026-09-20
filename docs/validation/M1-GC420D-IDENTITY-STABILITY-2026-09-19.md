# GC420d USB identity stability across reattachment — 2026-09-19

Closes the check [#128](https://github.com/bherila/macos-zpl-label-driver/issues/128) asked for, which
needed a person at the printer. It answers one question and no others: **does the serial number this unit
publishes survive reattachment?**

It does. Three perturbations, three `same` results.

## Privacy

This repository is public. No serial number, and no digest of one, appears here, in the commit, in the pull
request or in any log. The probe's `--fingerprint` output was written to a file outside the repository,
compared locally, and the files were deleted at the end of the session; their absence was verified. The only
values that left the comparison are the words `same` and `different`. The probe's default output, reproduced
below, is the publishable form and carries no serial.

## Environment

| Item | Value |
|---|---|
| Host | macOS 27.0, build 26A428, arm64 |
| Date | 2026-09-19 |
| Tool | `scripts/usb_identity_probe.py`, unmodified |
| Input | `ioreg -a -l -r -c IOUSBHostDevice` piped to the probe |
| Device | Zebra GC420d, USB, the reference unit |

Note the host is macOS **27.0**, not the `macos-26` the CI job runs. That difference does not affect this
result — `ioreg` output and a local digest comparison are not macOS-version-sensitive in any way this check
depends on — but it is recorded rather than left for a reader to assume.

## What was run

Reading the host I/O Registry is host observation, not printer I/O: it opens no device, claims no interface
and sends no byte. Nothing was transmitted to the printer at any point, no queue was installed, no
authorization was requested, and no label was consumed.

```sh
probe() { ioreg -a -l -r -c IOUSBHostDevice \
  | python3 scripts/usb_identity_probe.py --fingerprint \
  | grep -o 'fingerprint=[0-9a-f]*'; }
```

A baseline was captured, the maintainer performed each perturbation, and a fresh capture was compared to the
baseline. Every capture was non-empty, so no result is the false `same` that two empty captures would give.

## Results

| # | Perturbation | Performed by | Result |
|---|---|---|---|
| 1 | Unplug the USB cable, wait 30 seconds, plug it back in | maintainer | `same` |
| 2 | Printer power off, wait 10 seconds, power on | maintainer | `same` |
| 3 | Move the cable to a different USB port on the Mac | maintainer | `same` |

Result 3 carries the most weight. `locationID` is derived from the port, so an identity accidentally keyed on
topology rather than on the unit would have changed here, and it did not. Results 1 and 2 would both pass for
an identity that was quietly port-derived, because the cable went back into the same port.

## Publishable probe output, identical before and after each perturbation

```
1 USB device(s) visible, 1 from Zebra (VID 0x0A5F)
  VID 0x0A5F  PID 0x00D1  ZTC GC420d (EPL)
    printer-class interface(s): 0
    serial: PRESENT  length=12  classes=digits,upper  unit-distinct=yes
```

`printer-class interface(s): 0` is the interface **number**, not a count. The probe joins interface numbers
and prints `none seen` when the list is empty, so this line agrees with the single `bInterfaceClass` 7
interface already recorded in [GC420D.md](../hardware/GC420D.md) rather than contradicting it.

## #128 step 3, partially

`swift test --package-path Packages/LabelMac --filter USBDeviceIdentity` was run on this Mac against PR #123
at `cb732c1`: **`Executed 13 tests, with 0 failures`**. Those 13 cases had previously run only in hosted CI.

State what this does not show. Those tests drive #123's injected registry seam, not the live I/O Registry, so
this is macOS compile-and-logic evidence for that code and **not** a demonstration that it reads a real
device correctly. The real-registry half of step 3 — building the setup app and running *Discover USB Printer
Interfaces* — was **NOT RUN**.

## NOT RUN

- The GUI half of #128 step 3: no setup app was built or launched, and no qualification was exercised against
  the live registry.
- #128 step 4, the configuration label from the Feed button. It consumes a label and is the maintainer's call;
  it was not requested and no label was consumed. The EPL Line Mode question it would answer is therefore
  still open.
- Any transmission to the printer, queue installation, CUPS interaction, privileged operation, calibration,
  firmware access, signing verification or release step.

## What this unblocks, and what it does not

PR #123's premise — that this unit publishes an identity stable enough for a profile to bind to — holds. By
the table in #128, step 1 reading `same` is the condition under which #123 is ready to merge.

It qualifies no acceptance criterion by itself, establishes nothing about printing, and grants no consent to
install a queue, send a command or consume a label. A maintainer's informal report and a host-side
observation are different things from level-H device evidence, and this is the second kind.

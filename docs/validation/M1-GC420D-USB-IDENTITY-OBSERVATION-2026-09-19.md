# GC420d USB identity, observed read-only — 2026-09-19

The first host-side observation of the reference unit. **No acceptance ID advances and no evidence level is
claimed.** This is an observation that decides a design question; it is not qualification of the printer,
the transport, or any project backend.

## The question it answers

PR #123 implements per-unit USB identity qualification for issue #89 and fails closed: a unit that
publishes no usable serial number can never reach `.observed`, so queue installation stays unavailable.
Whether a GC420d publishes a serial at all was unobserved. If it did not, #123 would be correct and would
still unblock nothing. That question needed the hardware and nothing else.

## Environment and method

Apple Silicon Mac, macOS 27.0 (Darwin 27.0.0), the maintainer's GC420d attached by USB and powered on.
Run in a supervised session with the maintainer present, at the maintainer's direction.

```
ioreg -a -l -r -c IOUSBHostDevice | python3 scripts/usb_identity_probe.py
```

`ioreg` reads the kernel's I/O Registry. The probe reads that property list on standard input and nothing
else: it starts no process, opens no device, claims no interface and sends no command. **No byte was sent
to the printer**, so this consumed no label and used none of the physical-test budget in
`docs/VALIDATION-PLAN.md`.

## Result

Default probe output, verbatim, which is safe to publish because it never contains the serial:

```
1 USB device(s) visible, 1 from Zebra (VID 0x0A5F)
  VID 0x0A5F  PID 0x00D1  ZTC GC420d (EPL)
    printer-class interface(s): 0
    serial: PRESENT  length=12  classes=digits,upper  unit-distinct=yes
```

Key names only, never values, were also listed on the device node: the serial is carried under both
`USB Serial Number` and `kUSBSerialNumberString`, as strings — the names #123 reads. `sessionID` and
`locationID` are present too; they are session-scoped, which is why an identity must not be built from them.

So the premise of #123 holds for this unit: there is a per-unit serial, it is not a placeholder, and it is
reachable from read-only registry metadata.

## What this does not establish

- **Stability across reattachment is NOT YET OBSERVED.** The serial should survive an unplug and replug;
  that has not been checked. `--fingerprint` exists for exactly that local comparison.
- It does not show that #123's Swift code reads the value correctly on this machine. That code has run only
  in hosted CI against an injected registry seam. The key names match; the code path is unexercised here.
- It qualifies no transport, status channel, backend or print path, and installs nothing.
- One unit was observed. Nothing here generalizes to other GC420d units or firmware.

## Two corrections made while observing

**One printer looked like two.** macOS copies `idVendor`, `idProduct` and the serial onto the device's
`IOUSBHostInterface` child, so the first, throwaway version of the probe matched both nodes and reported
two Zebra devices with identical digests. There is one `IOUSBHostDevice`. The committed probe counts device
nodes, identified by `bDeviceClass`, and lists printer-class interfaces beneath them; a regression pins it.

**`(EPL)` is not what it appears to be.** The product string raised the question of whether a ZPL driver
is addressing an EPL printer. It is not a language statement. The GC420 specification lists EPL2 and ZPL II
together [R26](../REFERENCES.md#r26); Zebra documents automatic detection between them for the sibling
GK420d and a `device.pnp_option` setting that selects the plug-and-play identity string
[R47](../REFERENCES.md#r47). The maintainer separately reports that `lpr -l` prints ZPL correctly through
the existing queue, which is the only evidence specific to this unit and remains an informal
developer-baseline observation rather than level-H evidence. The limits of that research — a guide that
could not be fetched, a reference page that rendered only navigation — are stated in R47 rather than
smoothed over. The real hazard in this area is EPL Line Mode, recorded in `docs/hardware/GC420D.md`.

## Privacy

The serial number and every digest of it are recorded nowhere in this repository or its issues. The default
probe output omits both. Other vendors' devices are counted and never described, since a product string
can name a person's device. `test_the_serial_never_appears_in_any_output` and
`test_other_vendors_are_counted_but_never_described` pin both properties.

## Validation

macOS 27.0, CPython 3, at this commit. Exit status taken from each command itself, not from a pipeline:

| Command | Result |
|---|---|
| `python3 -m unittest scripts.tests.test_usb_identity_probe` | 12 tests, OK |
| `python3 scripts/check_repo.py` | preflight passed |
| `python3 -m unittest discover -s scripts/tests` | see the pull request for the count at its head |
| `python3 scripts/manifest_audit.py --enforce-covered --enforce-coverage` | exit 0 |
| probe against the attached unit | exit 0, output above |

**NOT RUN:** the Swift suites. No Swift file is touched by this slice. Nothing was printed, installed,
calibrated or authorized, and no administrator action was taken.

## Owed

This slice adds a script and edits `docs/hardware/`, neither exempt, so it stales `M2-AC04` and `M2-AC13`.
PR #123 will do the same when it merges. One re-seal after both covers them together.

# M1 — USB stable-identity qualification (2026-09-19)

Slice: bounded discovery-to-identity qualification for issue
[#89](https://github.com/bherila/macos-zpl-label-driver/issues/89).
Branch `codex/m3-t2-identity`, based on `main` at `eb70ca7`.

**This document qualifies no hardware.** No USB device was attached, opened, claimed, written to
or read from. No queue was installed, no privileged operation was attempted, and no printer was
contacted. Every observation in every test is a synthetic in-memory fixture, and every serial
number in this repository is an invented string. No acceptance criterion is claimed.

## Environment

| Item | Value |
| --- | --- |
| Host | Linux `6.18.44-fc-v37`, x86-64 |
| Swift | 6.1.3 (`x86_64-unknown-linux-gnu`) |
| Python | `python3` as installed on the host |
| Printer | none attached; none reachable from this host |
| macOS | none; no Apple SDK, no IOKit, no CoreGraphics, no CryptoKit |

`Packages/LabelMac` is macOS-only and **cannot be compiled on this host**. Its first real
compilation is the hosted `macos-26` CI job on the pull request. IOKit behaviour cannot be
exercised here at all, at any level. A Linux result validates none of macOS printing, Core
Graphics, the GUI, signing, USB, or a physical label printer.

## What this slice adds

`USBRegistryDiscovery` now reads one further read-only IORegistry property from the USB host
device entry it already reads the vendor and product identifiers from: the serial-number string,
which `IOKit/usb/USBSpec.h` names `kUSBSerialNumberString` / `"USB Serial Number"`. The kernel
populates that property during device enumeration. Reading it is a registry property read of the
same kind already performed; it is not a USB write, not a control transfer, and does not open or
claim a device or an interface.

`LabelCore` gains `USBIdentityQualification`, which decides whether an observation amounts to a
stable per-unit identity and derives an opaque one when it does, and
`PrinterProfile.adoptingStableIdentity(_:evidence:)`, which produces a new immutable profile
revision that differs only in its connection identity. `ReferencePrinterSetupModel` gains
`qualifyIdentity(from:)` and `withdrawQualifiedIdentity()`, which is the path by which an observed
identity reaches a profile — previously there was none, and `.observed` was never produced
anywhere in `Sources/`.

### Why a serial number, and nothing else

A USB vendor/product pair names a *model*. Two GC420d units publish the same pair, so the pair
cannot tell them apart. An IORegistry entry ID is scoped to the current session and does not
survive a replug or a reboot, which is why `USBPrinterObservation` keeps it private and documents
itself as session-only. The serial-number string is the only field in read-only registry metadata
a vendor intends to be per-unit and persistent.

That it *is* per-unit is a vendor claim. This code cannot verify it and does not imply otherwise.

### Design decision: a unit that reports no serial number

**A unit that reports no usable serial number does not become `.observed` by any route.** There is
no fallback to vendor/product, no fallback to the registry entry ID, and no "good enough"
path. `USBIdentityQualification.qualify` either returns a qualified identity or throws a typed
`Failure`; the setup model records `.refused(failure)` and the profile is not touched at all — not
its connection, not its revision, and not the stock or tear-off confirmations.

The refusal is reported as a specific reason rather than a bare "no", and the reasons are kept
apart because they are different facts about different problems:

| Failure | What was found |
| --- | --- |
| `serialNumberAbsent` | the device published no serial-number property |
| `serialNumberUnreadable` | a property existed but was not a usable string |
| `serialNumberEmpty` | the string was empty, or was only whitespace |
| `serialNumberUnprintable` | the string held a character outside printable ASCII |
| `serialNumberTooLong` | longer than a USB string descriptor can carry |
| `serialNumberNotUnitDistinct` | a placeholder such as `0` or `00000000` |
| `digestMalformed` | the digest did not return 64 lowercase hexadecimal characters |
| `identityRejected` | the derived value was refused by `StableConnectionIdentity` |

Collapsing "nobody has looked yet", "the device publishes nothing", and "a property was there but
could not be read" into one boolean is exactly how an unknown becomes a false. Each one is carried
to the person as its own sentence (`USBIdentityQualification.Failure.setupMessage`); no raw enum
case name reaches the UI, which the #89 session recorded as a defect elsewhere in this app.

`serialNumberNotUnitDistinct` is a deliberate, narrow screen: a string made of one repeated
character carries no per-unit information whatever the vendor intended. It is a floor, not a
uniqueness test. A vendor that ships every unit as `0123456789` is indistinguishable from one that
does not, and no read-only scan can tell them apart. The screen fails toward *not qualified*,
which is the direction that cannot invent a device.

### Design decision: the identity never carries the serial number

`StableConnectionIdentity.opaqueValue` is `"usb-sha256-"` followed by a SHA-256 digest, in
lowercase hexadecimal, of a domain-separated canonical preimage:

```
LABEL_USB_STABLE_IDENTITY_V1\n usb \n <VID as 4 hex digits> \n <PID as 4 hex digits> \n <serial> \n
```

Hashing rather than storing the serial is what keeps `AGENTS.md`'s prohibition on committing
printer serial numbers intact while still letting a stored profile bind to one unit: the profile,
its JSON encoding, the diagnostic surfaces and any log can hold the identity without holding the
serial. `RedactedDiagnosticValue` keeps working and is asserted to keep working.

Three properties of the encoding are load-bearing and are tested:

- **Domain separation.** The separator binds the digest to this derivation and this version of it,
  so a digest computed elsewhere over the same bytes can never be mistaken for a device identity,
  and a future change to the scheme can take a new separator rather than silently producing
  different identities under the same name.
- **Injectivity.** Fields are newline-separated, the identifiers are fixed-width, and the serial
  is already known to contain no newline. Without this, a vendor identifier ending in a digit and
  a serial beginning with one could run together and let two different units collide.
- **Normalisation.** Surrounding whitespace is trimmed, because descriptor padding is a property
  of how a descriptor was filled in rather than of the unit; the same physical printer must not
  produce two identities. What survives has to be printable ASCII, which also removes any Unicode
  normalisation question.

The digest itself is a seam (`StableIdentityDigest`), not an implementation. `LabelCore` carries
no dependencies and must build and test on a non-Apple host, where CryptoKit does not exist; and a
private SHA-256 written here would put unaudited cryptographic code on the one path that stands
between a serial number and everything that is stored or displayed. **Nothing in this repository
implements SHA-256.** The production conformance, `CryptoKitStableIdentityDigest`, is CryptoKit.
A conformance is not trusted either: qualification rejects any return value that is not exactly 64
lowercase hexadecimal characters, so a wrong or hostile digest yields a reported failure rather
than an identity.

### What this does and does not unblock

Qualification is identity qualification and nothing else. It installs no queue, requests no
authorization, opens no device and sends no command.

`canInstallQueue` had three conjuncts and still has three: control validation, the
`stockLoadedConfirmed` and `tearOffConfirmed` confirmations, and an observed identity. Only the
third was previously unsatisfiable. Neither confirmation was weakened; in fact qualifying a
*different* unit now **withdraws** both, because they were made about whatever printer was in
front of the person at the time and do not carry over to another one. Re-qualifying the unit
already adopted is idempotent: it spends no profile revision and withdraws nothing.

Adoption advances the profile revision. A job binds an immutable profile revision, so rewriting
the connection in place under the same revision would move the snapshot boundary without anything
being able to observe that it moved.

## Commands and exact results

All run on the Linux host described above, at the tree of this slice.

| Command | Result |
| --- | --- |
| `python3 scripts/check_repo.py` | **PASS**, exit 0 — `Repository preflight passed (links, metadata, milestone files, action pins).` |
| `python3 -m unittest discover -s scripts/tests` | **PASS** — `Ran 161 tests` … `OK (skipped=2)` |
| `swift test --package-path Packages/LabelCore` | **PASS** — `Executed 338 tests, with 0 failures (0 unexpected)`; baseline before this slice was 326, so the 12 new `USBDeviceIdentityQualificationTests` cases are additions and no existing test changed |
| `python3 scripts/run-accelerator-checks.py` | **PASS** — `PASS: offline accelerator suite. macOS/scheduler/hardware qualification is separate.` |
| `git diff --check` | clean, exit 0 |
| `swiftc -frontend -parse` on each changed Swift file | parses; **syntax only, not type checking** |
| `sha256sum -c MANIFEST.sha256` | **PASS** — every listed file verifies after re-hashing the covered files this slice changed |

`swiftc -frontend -parse` is reported for completeness and proves nothing beyond well-formed
syntax. It does not resolve names, check types, check actor isolation, or see an SDK.

### Tests added

`Packages/LabelCore/Tests/LabelCoreTests/USBDeviceIdentityQualificationTests.swift` (12 cases, run
on this host): a unit with a serial qualifies; a unit without one does not, for each of the ten
distinguishable ways it can fail; two units of one model with different serials produce different
identities; two models with the same serial do too; the same unit produces the same identity on a
second pass, including through descriptor padding; the identity never carries the serial and stays
redacted under `dump`, `description` and reflection; a reading will not hand back the string it
holds; the canonical preimage separates its fields unambiguously; a malformed digest fails closed;
adoption advances the revision and changes nothing else; adoption refuses unobserved evidence and
an unrepresentable revision; an adopted identity survives the profile codec without revealing
itself.

`Packages/LabelMac/Tests/LabelMacTests/USBDeviceIdentityTests.swift` (13 cases, **NOT RUN here** —
macOS only): the same properties through the setup model, plus the CryptoKit digest against the
published FIPS 180-4 `"abc"` vector, the serial-number property classifier, every refusal reason
having its own sentence, `canInstallQueue` staying false until every gate is satisfied,
withdrawal returning the gate to blocked, an observation defaulting to no serial so it fails
closed, and the picker's selection remaining inert with qualification as a separate action.

## What remains unqualified

- **Every hardware fact.** No GC420d was attached. Whether a GC420d publishes a serial-number
  string at all, and what it contains, is **unobserved**. The #89 session's scan reported
  `USB VID 0x0A5F, PID 0x00D1, interface 0` and nothing about a serial number, because nothing
  read one. If the unit publishes none, the correct outcome of this code is `serialNumberAbsent`
  and installation stays blocked — that is the design, not a failure of it, and it would mean a
  different identity source is needed for that unit.
- **Whether the IORegistry property key and placement are right in practice.** The key is taken
  from the public header and read from the `IOUSBHostDevice` parent entry. That it is present
  there for this device, on this macOS version, is unverified.
- **That the LabelMac changes compile.** They have never been type-checked.
- **Delivery.** Identifying a unit says nothing about whether bytes can reach it. The transport
  fact says so in those words.
- **Installation.** Untouched by this slice and still unimplemented and separately authorized.
- **Per-unit uniqueness of any vendor's serial numbers.** A vendor claim this code cannot verify.

## NOT RUN

- `swift test --package-path Packages/LabelMac` — **NOT RUN.** macOS-only; no Apple SDK on this
  host. The 13 new LabelMac test cases have never executed.
- `bash scripts/ci-swift.sh` — **NOT RUN.** Requires a Mac.
- Any compilation or type check of `Packages/LabelMac` — **NOT RUN.** First attempt is hosted
  `macos-26` CI on the pull request; iteration should be expected.
- Any IOKit call, registry scan, or `system_profiler` cross-check — **NOT RUN.** No IOKit here.
- Any GUI session, application launch, or interaction with `Label Printer Driver Setup.app` —
  **NOT RUN.**
- Any USB device attachment, enumeration, open, claim, read or write — **NOT RUN.**
- Any queue installation, CUPS interaction, administrator authorization or privileged helper
  operation — **NOT RUN**, and out of scope for this slice.
- Any printing, calibration, firmware or persistent-settings operation — **NOT RUN.**
- Local ad-hoc signing verification — **NOT RUN.** Requires a Mac.
- Any release, publication or distribution step — **NOT RUN.**

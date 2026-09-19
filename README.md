# Label Printer Driver for macOS

A Swift-first, open-source macOS printing system for ZPL-compatible label printers.

**Not yet a usable driver. No printer model is qualified, no queue can be installed, and this project has
never sent a byte to a printer.** What exists is a tested imaging and workflow core, an offline setup and
workflow-editing app, and an evidence system that keeps those claims honest.

The goal is ordinary application printing with sharp label imaging, printer-specific controls, saved
media and workflow defaults, and automatic extraction of labels from Letter/A4 documents. Apple Silicon
is the primary target. This project is independent of printer manufacturers and commercial driver vendors.

## Status — 2026-09-19

This snapshot is dated because it will age. `python3 scripts/evidence_currency.py` prints the live figures.

| Area | State |
|---|---|
| Imaging core (`LabelCore`) | Geometry, one-bit layout, ZPL graphic encoding and compression, profiles, tickets. Builds and tests on Linux and macOS. |
| macOS layer (`LabelMac`) | Quartz PDF rendering, an isolated render worker, workflow store, finishing pipeline with inert delivery. Tested on hosted `macos-26` ARM. |
| Setup app | Offline workflow editor with exact packed-bitmap preview and read-only USB discovery. CI builds, ad-hoc signs and uploads it from `main`. No GUI acceptance is complete. |
| Printing | **None.** No CUPS queue, backend or transport is installed or qualified. |
| Reference hardware | Zebra GC420d, USB, 4×6 pre-cut, tear-off. Its USB identity was observed read-only; nothing else about the unit is. See [reference hardware](docs/hardware/GC420D.md). |
| Acceptance | 90 criteria. 13 boxes are checked, **2 are qualified** by a current digest-bound record, and 11 checked boxes have no record at all. The report says so rather than hiding it. |

### What is blocked, and on what

Most remaining criteria cannot be advanced from CI. Each is tracked:

- **Queue installation is structurally unavailable** until a per-unit USB identity is qualified —
  [#89](https://github.com/bherila/macos-zpl-label-driver/issues/89), implemented in
  [#123](https://github.com/bherila/macos-zpl-label-driver/pull/123), waiting on a hands-on check in
  [#128](https://github.com/bherila/macos-zpl-label-driver/issues/128).
- **GUI and installed-scheduler criteria** need a supervised Mac session —
  [#80](https://github.com/bherila/macos-zpl-label-driver/issues/80).
- **Hardware and release criteria** need the printer and a release gate —
  [#90](https://github.com/bherila/macos-zpl-label-driver/issues/90).

The [open issues](https://github.com/bherila/macos-zpl-label-driver/issues) are the authoritative list.

## Planned capabilities

- Print directly from macOS applications, including tested browser shipping workflows.
- Control supported speed, darkness, media tracking, thermal method, offsets, cutters and peelers.
- Preserve PDF detail until final-resolution rendering; preview the actual monochrome output.
- Extract, rotate, scale and order one or multiple labels from larger pages using validated profiles.
- Create several virtual printers for one physical device without interleaving their output.
- Install, configure, diagnose, update and remove the system through a native application.

These are roadmap items, not statements of implemented or universal support. A low-resolution or
already-clipped source cannot be repaired merely by installing a driver.

## Build and test

Requires a Swift 6-or-newer toolchain. The macOS package also needs Apple's macOS SDK, a macOS 26+ host
and an SDK of at least 26.0. No older-runtime support is planned. A deployment target is not a
qualification claim.

```sh
python3 scripts/check_repo.py
python3 -m unittest discover -s scripts/tests
python3 scripts/run-accelerator-checks.py
swift test --package-path Packages/LabelCore
# macOS only:
swift test --package-path Packages/LabelMac
bash scripts/ci-swift.sh          # the CI-equivalent build, test and local-signature sequence
```

None of these needs `sudo`, and none enumerates, installs, configures or prints to a device.
**[docs/BUILDING.md](docs/BUILDING.md) is the full guide**: requirements per platform, the Linux CUPS
header dependency, running a single test, building and identifying the setup app, and the pre-commit steps.
`Packages/LabelMac` cannot build on Linux; hosted `macos-26` is its compile gate for work written there.

### Offline PDF conversion (development only)

`label-driver` is a local, non-printing converter. Its ticket carries page, physical geometry, resolution
and monochrome policy; it cannot carry output paths, printer controls or transport settings.

```sh
mkdir -p /tmp/label-driver-preview
swift run --package-path Packages/LabelMac label-driver convert \
  Fixtures/generated/native-vector.pdf \
  --job-ticket Examples/offline-ticket-v1.json \
  --output /tmp/native-vector.zpl \
  --preview-dir /tmp/label-driver-preview \
  --json
```

`validate` performs the same bounded preparation without writing artifacts, and `convert` refuses to
overwrite either output. The `.zpl` file is an offline graphics envelope: it deliberately does not
normalize printer state and **must not be sent to a printer**. The PBM preview is an exact expansion of
the packed bitmap supplied to that envelope.

### Observing the printer without touching it

```sh
ioreg -a -l -r -c IOUSBHostDevice | python3 scripts/usb_identity_probe.py
```

Reads the host's I/O Registry and nothing else. It never prints a serial number, so its default output is
safe to post. Never post a serial or the `--fingerprint` value.

## How claims are kept honest

A checked box is a claim, not evidence. The ledger asks four separate questions of every acceptance
criterion — is the box checked, do the cited bytes still hash to what was recorded, does the record still
describe the current source, and is it at the level the criterion prescribes (automated, configuration,
macOS integration, hardware, release). A criterion is **qualified** only when one single record answers
all four. Compiled, simulated, GUI-tested and physically printed are never treated as the same thing.

Two consequences shape day-to-day work, and both are enforced by CI:

- **Evidence follows source, in its own change.** Any change outside a short list of bookkeeping paths
  makes existing records stale until a following change re-seals them against the merged result.
- **`MANIFEST.sha256` covers every tracked file.** Run `python3 scripts/refresh_manifest.py --backfill`
  after staging your files.

[CONTRIBUTING.md](CONTRIBUTING.md) has the commands; [docs/TRACEABILITY.md](docs/TRACEABILITY.md) has the
rules; [docs/VALIDATION-PLAN.md](docs/VALIDATION-PLAN.md) defines the evidence levels.

## Architecture and roadmap

The portable Swift package owns job, geometry, profile and encoding logic. The macOS package owns Quartz
and operating-system adapters. A native application provides setup and workflow editing. The CUPS/PPD
approach remains an experiment until macOS integration tests establish its behavior; an IPP adapter is an
independently evaluated path.

Start with [START-HERE.md](START-HERE.md), the [epic](EPIC.md) and [architecture](docs/ARCHITECTURE.md).
Read [compatibility](docs/COMPATIBILITY.md) before assuming a model or OS is supported, and
[docs/HANDOFF.md](docs/HANDOFF.md) for the most recent work, newest first.

## First hardware and local signing

The first intended configuration is **GC420d / USB / 4×6 pre-cut labels / tear-off**, on **macOS 26+ /
Apple Silicon**. This model is direct thermal; ribbon, cutter and peeler features are not enabled for it.

Local ad-hoc signing is the default and needs no Apple Developer account. On a Mac,
`bash scripts/host-preflight.sh` checks the build host and `bash scripts/sign-local-diagnostic.sh` signs
and executes the inert diagnostic only. Neither installs a driver or sends a printer command. A
source-build local install is distinct from a Developer-ID-notarized download; see
[local signing](docs/LOCAL-SIGNING.md) and [release scopes](docs/RELEASE-SCOPES.md).

## Contributing and security

Read [CONTRIBUTING.md](CONTRIBUTING.md), [AGENTS.md](AGENTS.md) and [SECURITY.md](SECURITY.md). Do not
upload real shipping labels, customer information, credentials, printer serial numbers or proprietary
driver artifacts. Use synthetic fixtures or explicitly cleared samples.

New project code is MIT-licensed; see [LICENSE](LICENSE). Dependency licenses and notices remain their
own. This repository does not contain or require proprietary third-party driver implementation.

See [the accelerator guide](docs/ACCELERATOR.md) for the independent ZPL oracle, generated synthetic
fixtures and the discard-only CUPS probe. Candidate PPDs are not production profiles.

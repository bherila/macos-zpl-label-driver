# Label Printer Driver for macOS

A Swift-first, open-source macOS printing system for ZPL-compatible label printers.

**Development status: tested portable core components and integration experiments. Not yet a usable driver. No printer model is currently qualified.**

The goal is ordinary application printing with sharp label imaging, printer-specific controls, saved media/workflow defaults, and automatic extraction of labels from Letter/A4 documents. Apple Silicon is the primary target. This project is independent of printer manufacturers and commercial driver vendors.

## Planned capabilities

- Print directly from macOS applications, including tested browser shipping workflows.
- Control supported speed, darkness, media tracking, thermal method, offsets, cutters and peelers.
- Preserve PDF detail until final-resolution rendering; preview the actual monochrome output.
- Extract, rotate, scale and order one or multiple labels from larger pages using validated profiles.
- Create several virtual printers for one physical device without interleaving their output.
- Install, configure, diagnose, update and remove the system through a native application.

These are roadmap items, not statements of implemented or universal support. A low-resolution or already-clipped source cannot be repaired merely by installing a driver.

## Build the current development components

Requires a Swift 6-or-newer toolchain. The macOS package also requires Apple's macOS SDK. The Mac deployment target is 26.0 (Tahoe); use a macOS 26+ host with an SDK at least 26.0. No older-runtime support is planned. Deployment target is not a qualification claim.

```sh
python3 scripts/run-accelerator-checks.py
swift test --package-path Packages/LabelCore
# On macOS only:
swift test --package-path Packages/LabelMac
swift run --package-path Packages/LabelMac label-driver-diagnostics
python3 scripts/check_repo.py
python3 -m unittest discover -s scripts/tests
```

The diagnostic performs a tiny Core Graphics smoke test. It does not enumerate, install, configure, or print to a device. No `sudo` is needed for these commands.

### Offline PDF conversion (development only)

The macOS package also provides a local, non-printing converter. Its ticket
contains page, physical geometry, resolution, and monochrome policy; it cannot
contain output paths, printer controls, or transport settings. For a synthetic
fixture:

```sh
mkdir -p /tmp/label-driver-preview
swift run --package-path Packages/LabelMac label-driver convert \
  Fixtures/generated/native-vector.pdf \
  --job-ticket Examples/offline-ticket-v1.json \
  --output /tmp/native-vector.zpl \
  --preview-dir /tmp/label-driver-preview \
  --json
```

`validate` performs the same bounded preparation without writing artifacts.
`convert` refuses to overwrite either output. The `.zpl` file is an offline
graphics envelope; it deliberately does not normalize printer state and must
not be sent directly to a printer. The PBM preview is an exact expansion of
the packed bitmap supplied to that envelope. Neither command enumerates,
installs, configures, or contacts a printer.

## Architecture and roadmap

The portable Swift package owns job/geometry/profile/encoding logic as it is implemented. The macOS package owns Quartz and operating-system adapters. A separate native application will provide setup and workflow editing. The initial CUPS/PPD approach is an experiment until macOS integration tests establish its behavior; an IPP adapter remains an independently evaluated path.

Start with [START-HERE.md](START-HERE.md), the [epic](EPIC.md), and [architecture](docs/ARCHITECTURE.md). See [compatibility](docs/COMPATIBILITY.md) before assuming a model or OS is supported.

## Contributing and security

Read [CONTRIBUTING.md](CONTRIBUTING.md), [AGENTS.md](AGENTS.md), and [SECURITY.md](SECURITY.md). Do not upload real shipping labels, customer information, credentials, or proprietary driver artifacts. Use synthetic fixtures or explicitly cleared samples.

New project code is MIT-licensed, confirmed by the maintainer; see [LICENSE](LICENSE). Dependency licenses and notices remain their own. This repository does not contain or require proprietary third-party driver implementation.

## First hardware and local signing

The first intended configuration is **GC420d / USB / 4×6 pre-cut labels / tear-off**, on **macOS Tahoe 26+ / Apple Silicon**. No configuration is qualified yet. This model is direct thermal; do not enable ribbon/cutter/peeler features for the selected setup. See [reference hardware](docs/hardware/GC420D.md).

Local ad-hoc signing is the default and needs no Apple Developer account. On a Mac, `bash scripts/host-preflight.sh` checks the build host; `bash scripts/sign-local-diagnostic.sh` signs and executes the inert diagnostic only. Neither installs a driver or sends a printer command. The source-build/local-install scope is distinct from a Developer-ID-notarized download. See [local signing](docs/LOCAL-SIGNING.md) and [release scopes](docs/RELEASE-SCOPES.md).

## Implementation head start

See [the accelerator guide](docs/ACCELERATOR.md) for existing Swift packing/encoding/order code, an independent ZPL oracle, generated synthetic fixtures and the discard-only CUPS probe. Candidate PPDs are not production profiles. The [validation report](docs/ACCELERATOR-VALIDATION.md) distinguishes actual offline results from unperformed Mac/hardware gates.

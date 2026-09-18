# Evidence — M5 conservative reference-printer setup UI

- Date/time and operator: 2026-09-15, automated local Codex session
- Exact repository commit SHA: `349731e`
- Related requirement and acceptance IDs: F08, F11, N04, M5-AC01,
  M5-AC04, M5-AC05, M5-AC10
- Evidence level: A/C plus a narrow local launch observation; no acceptance row
  is closed
- Status: PASS for model/view automation and ordinary local process launch;
  NOT RUN for visual, VoiceOver, installation, scheduler, and device behavior
- Environment: macOS 26.6.2 build 25G83, arm64, Xcode 26.6 build
  17F113, Swift 6.3.3, SDK 26.5
- Application path: local SwiftUI setup app
- Printer/transport/stock: reference GC420d USB and reported 4x6 pre-cut
  direct-thermal/tear-off setup only; no printer identity was discovered and no
  device was accessed
- Hardware/installation authorization: not required; zero labels, zero device
  commands, zero privileged operations, and zero scheduler changes

## Procedure

```sh
swift test --package-path Packages/LabelMac --filter ReferencePrinterSetupTests
swift test --package-path Packages/LabelMac
bash scripts/build-local-app.sh
open -n 'artifacts/<run>/Label Printer Driver Setup.app'
/usr/bin/osascript -e 'tell application id "net.bherila.label-printer-driver.setup" to quit'
bash scripts/ci-swift.sh
```

The ignored run-specific artifact directory is represented by `<run>` above.
Process observation checked that the app executable started and terminated
after the ordinary quit request.

## Expected and observed results

All four focused setup tests passed. The full CI-equivalent run passed 56
Python tests, 130 LabelCore tests, and 74 LabelMac tests in both debug and
release, together with 132 independent graphics round trips, 15 backend ABI
cases, ten filter ABI cases, one inert pipeline, and local-ad-hoc command-line
and app signature checks.

The setup model is derived from the typed reference profile. It shows the
reported GC420d, USB transport, 4x6 pre-cut direct-thermal stock, and tear-off
mode while keeping the USB device identity unobserved. It exposes only the
documented 2/3/4 inches-per-second choices and validates any session selection
through `PrinterProfile.validate`. Cutter is unavailable for the selected
setup; peeler, darkness, and installed tracking remain explicitly unqualified
or unobserved. No raw identity enters the displayed facts.

Stock and tear-off confirmation gate the local PDF workflow step. Queue
installation remains unavailable even after those confirmations because a
reported USB transport is not a discovered stable device identity. The speed
picker is explicitly labeled as a session draft, with text stating that it is
not saved and changes no printer setting.

The signed app launched as a normal process and quit cleanly. The computer-use
UI inspection runtime failed to start on this host, so no visual or
accessibility-tree result is claimed.

## Artifacts

- `Packages/LabelMac/Sources/LabelMac/ReferencePrinterSetup.swift`
- `Packages/LabelMac/Sources/LabelSetupApp/main.swift`
- `Packages/LabelMac/Tests/LabelMacTests/ReferencePrinterSetupTests.swift`

## Limitations / next action

This does not establish USB discovery, installed defaults, queue creation,
keyboard traversal, VoiceOver, visual layout, restart behavior, or physical
output. The draft speed is intentionally not persisted; M5.2 must bind saved
defaults to an owned virtual queue/profile revision. A later discovery slice
must supply an observed stable identity before any install action can become
available. The M1 administrative experiment and privileged installation remain
separate authorized gates.

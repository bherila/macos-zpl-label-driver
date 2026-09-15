# Evidence — M3 automated profile and controls

- Date/time and operator: 2026-09-15, automated local Codex session
- Exact repository commit SHA: `7ee78db2f4fc8764d51b2c337896a0b5c9145e5a`
- Related requirement and acceptance IDs: F08, F09, F10, M3-AC01,
  M3-AC02, M3-AC04, M3-AC13
- Evidence level: A
- Status: PASS
- Environment: macOS 26.6.2 build 25G83, arm64, Xcode 26.6 build
  17F113, Swift 6.3.3
- Application path: portable typed profile, option resolver, control encoder,
  prepared-label encoder, and delivery-state contracts
- Printer/transport/stock: declared GC420d reference profile, USB, nominal 4x6
  pre-cut direct-thermal stock, tear-off; no device was accessed
- Fixture/profile revision: `PrinterProfile.gc420dUSBReference`, schema 1;
  tests exercise multiple immutable revisions
- Hardware/installation authorization: not required; zero labels, zero device
  commands, and zero system changes

## Procedure

At the exact commit above, the complete portable suite and the focused native
raw-TCP suite were run:

```sh
swift test --package-path Packages/LabelCore
swift test --package-path Packages/LabelMac --filter RawTCPDeliveryTests
```

The raw-TCP run is context for open transport rows; it is not used to close a
real-network, scheduler, USB, or hardware criterion.

## Expected and observed results

LabelCore passed all 98 tests. The focused native suite passed all eight
`RawTCPDeliveryTests`.

- **M3-AC01:** the reference profile represents supported, unsupported, and
  unknown as separate typed states with separate model-documentation,
  reported-installation, and unobserved evidence. Cutter is unknown at model
  level but absent for the installed configuration; peeler remains unobserved
  and cannot be selected. Observations are not defaults or authorization.
- **M3-AC02:** every field in `PrinterControlRequest` has explicit validation.
  The baseline accepts only direct thermal, tear-off, and documented 2/3/4 ips
  speed choices. Thermal transfer, cut, peel, rewind, speed 1/5, darkness,
  tracking, and unqualified device geometry fail rather than clamp or disappear.
  Unsupported workflow defaults fail through the same path.
- **M3-AC04:** `ZPLControlEncoder` accepts no raw strings and can emit only the
  qualified tear-off and speed commands. Exact-output regressions exclude reset,
  calibration, persistent save, erase/download, firmware, copy, and unqualified
  darkness/media-dimension/offset commands from ordinary prepared output.
- **M3-AC13:** the reference profile fixes documented 8-dots/mm geometry,
  2/3/4 ips choices, direct thermal, USB, pre-cut nominal 4x6 media, and tear-off.
  It rejects transfer/cut/peel/rewind and raw-TCP substitution while preserving
  sensing, calibration, connection identity, and current settings as unknown.

The prepared-label regressions additionally prove that resolved controls,
encoded bytes, media facts, connection configuration, and profile revision are
bound in one immutable snapshot before delivery. This supports the four rows
above but does not close any installed-transport row.

## Artifacts

- `Packages/LabelCore/Sources/LabelCore/PrinterProfile.swift`
- `Packages/LabelCore/Sources/LabelCore/PrinterControlResolution.swift`
- `Packages/LabelCore/Sources/LabelCore/ZPLControlEncoder.swift`
- `Packages/LabelCore/Tests/LabelCoreTests/PrinterProfileTests.swift`
- `Packages/LabelCore/Tests/LabelCoreTests/ZPLControlEncoderTests.swift`
- `Packages/LabelCore/Tests/LabelCoreTests/ZPLPreparedLabelEncoderTests.swift`

## Limitations / next action

This does not close full control coverage (M3-AC03): darkness, tracking,
calibrated dimensions/offsets, and additional finishing commands intentionally
remain unavailable until their semantics and installed state are qualified. It
also does not close network completeness (M3-AC05), USB (M3-AC06), real
cross-process ownership (M3-AC07/08), scheduler-visible uncertainty (M3-AC09),
physical finishing/state isolation (M3-AC10/11), or the complete privacy/status
frame contract (M3-AC12). Those rows retain their prescribed evidence gates.

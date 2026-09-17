# Complete implemented-control protocol metadata

Advances M3-AC03; full per-ID assessment remains pending. The earlier full-scope audit at b12e65a recorded this missing table as an independent software gap; retain it as historical evidence.

ZPLControlProtocol now has explicit implementedRange and modelLimits fields with compatible initializer defaults. Existing baseline speed/tear-off and qualified speed/thermal/darkness rows state concrete domains and independent qualification requirements. documentedControls maps every one of the twelve ZPLDocumentedControl.Kind cases to cited command, range, lifetime, interactions and model limits. qualifiedFinishingControls covers tear-off/cut/peel/rewind separately. These are inspection metadata, not command construction or capability admission; runtime encoder bytes and reference hardware constraints are unchanged.

New rows include gap, continuous mode/length, black-mark offset, width, both home axes, shift and top. R45 is existing public ordinary-command provenance; R46 supplies continuous-mode/length semantics. Width 2...32000 is explicitly an implementation subset intersecting label/model/head declarations, not a universal protocol ceiling. All newly supplied model-specific persistence is marked unverified, rather than assuming physical state isolation.

Cut metadata covers both twins: bounded offline ^MMC inspection grants no scheduling authority; native ^MMD and separate ~JK files require independent delayed-cut/file/status qualification. Native framing retains quantity 1 and observed readiness/completion boundaries; peel prepeel policy is independently qualified and label-taken waits retain ownership. Unknown unit sensing/accessories/status remain unknown. GC420d reference remains print speed 2/3/4 ips and tear-off, with cutter absent and peel disabled.

Validation: focused ZPLControlProtocolCoverageTests passed two tests exit 0. Full LabelCore debug/release passed 301 tests exit 0; debug accelerator passed 106 Python tests, 132 strict bitmap round-trips, 180 compression round-trips, 12 finite CLI cases, 15 CUPS ABI, 14 filter ABI and one inert discard pipeline. After a final metadata-only correction explicitly adding offline ^MMC to the cut row, the final two coverage tests passed debug/release exit 0. The earlier full suite/accelerator precede only that row string/test refinement; they are not mislabeled as a new whole-source native baseline. Encoder/qualification/graphics code and oracle were unchanged.

The coverage checks enumerate every documented kind, require its cited command/range/model/interaction metadata, enumerate all finishing modes, and assert the conservative reference and unverified accessory persistence. No new product target or dependency was introduced. Native app/GUI, scheduler/admin, Linux, physical printer and release tests were NOT RUN for this metadata slice. The prior complete native baseline and ledger records are historical after this source change. No per-ID pass was mechanically refreshed.

No printer I/O, queue modification, privilege, persistent device action, merge or release occurred. The frozen M1 Part B candidate remains unchanged. Next: assess M3-AC03 against all emitted normal/finishing routes and cited semantics at a current evaluated checkpoint, then continue the remaining automated/full-scope gaps.

Packages/LabelCore/Sources/LabelCore/ZPLControlEncoder.swift: 5a11110def21581dc46eddd277f64f153e289fe855bc9a2e75b9fb2bc74f6575

Packages/LabelCore/Sources/LabelCore/ZPLControlProtocolCoverage.swift: c5e28f592c2cefbe55757a067be28f18e31e452ac043c79ea932e7369c30ee1d

Packages/LabelCore/Tests/LabelCoreTests/ZPLControlProtocolCoverageTests.swift: 468ecf4ab8e410ece44ddf06cee0910ee4ccb4a03e4b914bedb8756ea998358c

# Evidence — M3-AC01 and M3-AC02 control-qualification coverage, proved by mutation

- Date/time and operator: 2026-09-21, automated Claude session, unattended
- Exact repository commit SHA: base `96e33918299fc82a48c5289e4452c39a6f974c37`
  (`origin/main`). Every command below was executed on branch
  `claude/m3-capability-truthfulness-coverage`, whose only difference from that
  base is this document and the new test file it cites. **No ledger record is
  written by this slice and no acceptance checkbox is checked.** This is a
  source slice; binding a criterion to a merged SHA is a separate controller
  slice against the merged result (see `docs/TRACEABILITY.md` and the
  "Evidence ledger and sequencing" section of `AGENTS.md`).
- Related requirement and acceptance IDs: M3-AC01 (capability truthfulness) and
  M3-AC02 (settings validation), both of which requirement F04 depends on.
  Neither box was checked before this slice and neither had any ledger record.
- Evidence level: A
- Status: PASS for the clauses tabulated below; the limitations section names
  every clause this run does **not** reach.
- macOS/Linux, architecture, Swift, Xcode/SDK, runner image (as applicable):
  Linux `x86_64-unknown-linux-gnu`, Swift 6.1.3 release toolchain, CPython
  3.11.15. No Xcode, no macOS runner, no `Packages/LabelMac` build — that
  package cannot build on Linux.
- Application/version and system-dialog versus browser-preview path: portable
  `LabelCore` typed profile, control resolution and offline control
  qualification only. No GUI, no dialog, no preview path.
- Printer model, resolution, firmware family, transport, stock/accessories (no
  serial): none. No printer was opened, addressed or sent anything. Every
  capability fact in the new tests is a synthetic fixture whose
  `documentedModel` source IDs are literally named `synthetic-…`.
- Fixture ID/hash and generator version: no committed fixture corpus is read or
  written. All fixtures are constructed in-process by the test file.
- Profile/job-ticket revision/hash: synthetic profile revisions 2, 3 and 7 are
  constructed in-process; no stored profile is read or written.
- Explicit hardware/installation authorization and finite label/command budget:
  not required and not requested. Zero labels, zero device commands, zero
  system changes, zero network access.

## The two criteria, clause by clause

`docs/milestones/03-printer-controls/ACCEPTANCE.md` states them as:

- **M3-AC01 (A):** "Unknown, absent and unsupported remain distinct; unverified
  accessory controls are not enabled silently."
- **M3-AC02 (A):** "Every explicit choice is range/combination checked;
  unsupported options fail instead of silently clamping or dropping."

They are reinforced by two standing `AGENTS.md` invariants: "Unknown capability
/status is not false, zero, supported or completed", and "Invalid device
settings fail validation rather than being clamped without disclosure."

## Procedure

A passing test is not proof that a guard is covered. Following `AGENTS.md`
("Prove a coverage claim by mutation: remove the guard, watch the named test
fail, byte-restore"), **89 separate mutations** were applied to the control
qualification sources, one at a time. Each mutation removed or weakened exactly
one guard, the full portable suite was run, the named failing tests were
recorded, and the file was then restored from an in-memory copy of its original
bytes. After every single run the harness re-computed the file's SHA-256 and
compared it with the pre-mutation digest, and ran `git diff --quiet`; both
checks passed for all 89 runs, so no mutation survived into the tree. Several
mutations touched files this lane may not edit (the qualification sources
themselves); they were byte-restored under the same check.

Knowing that a guard is uncovered does not say what removing it *does*, and an
earlier revision of this document reasoned about that instead of measuring it
and got it wrong for five guards. A second, separate pass therefore classified
the twelve empirically. A temporary, uncommitted probe (deleted before the
commit; it is scaffolding, not a test, and asserts nothing) exercises exactly
the invalid inputs the new tests use and prints, for each, whether a value came
back or an error was thrown and which. It was run once on the unmutated tree as
a control — all sixteen probe inputs rejected, with the errors the new tests
assert — and then once under each of the twelve mutations, byte-restoring the
mutated source and re-checking its SHA-256 after every run:

```sh
swift test --package-path Packages/LabelCore --filter M3ProbeClassificationTests
```

Part 2 reports that measurement. `git status --porcelain` is empty at the
commit: the probe file is gone and every mutation is restored.

Baseline and post-change runs:

```sh
swift test --package-path Packages/LabelCore    # before: Executed 346 tests, with 0 failures
swift test --package-path Packages/LabelCore    # after:  Executed 354 tests, with 0 failures
python3 scripts/check_repo.py
python3 -m unittest discover -s scripts/tests
python3 scripts/evidence_currency.py
```

Files mutated: `PrinterProfile.swift`, `PrinterControlResolution.swift`,
`FinishingControlQualification.swift`, `ThermalControlQualification.swift`,
`FinishingOutputQualification.swift`, `FinishingProfileConfiguration.swift`,
`OffsetControlQualification.swift`, `PhysicalGeometryQualification.swift`,
`LegacyHostStatus.swift`, `USBDeviceIdentityQualification.swift`,
`ProbeOptions.swift` — all under
`Packages/LabelCore/Sources/LabelCore/`.

## Expected and observed results

### Part 1 — 77 of 89 guards were already covered

Each row is one mutation. "Killed by" names a test that failed with the guard
removed and passes with it restored. Where several tests failed, the most
specific is named first. Full suite counts were 346 tests before this slice.

| # | Guard removed or weakened | Clause | Killed by |
|---|---|---|---|
| M01 | `validate`: finishing must be `.tearOff` | AC01 | `PrinterProfileTests.testGC420dRejectsForgedUnsupportedAndUnverifiedControls` (+4) |
| M02 | print-speed choice membership | AC02 | `PrinterProfileTests.testGC420dAcceptsOnlyDocumentedSpeedChoicesAndTearOff` (+7) |
| M03 | feed-speed capability-state guard | AC01 | `MotorSpeedIntegrationTests.testUnknownUnsupportedAndIncompleteRemainDistinct` |
| M04 | feed-speed choice membership | AC02 | `MotorSpeedIntegrationTests.testUnknownUnsupportedAndIncompleteRemainDistinct` (+1) |
| M06 | backfeed-speed choice membership | AC02 | `MotorSpeedIntegrationTests.testUnknownUnsupportedAndIncompleteRemainDistinct` (+1) |
| M07 | all-three-motor-speeds-together | AC02 | `MotorSpeedIntegrationTests.testInvalidQualifiedCapabilitiesAndLegacyVersionsFail` (+1) |
| M08 | darkness `evidence != .unobserved` | AC01 | `DarknessIntegrationTests.testLegacyAndUnqualifiedProfilesRemainUnavailable` |
| M09 | darkness `state == .supported` | AC01 | `DarknessIntegrationTests.testLegacyAndUnqualifiedProfilesRemainUnavailable` |
| M10 | darkness `0...30` range | AC02 | `DarknessIntegrationTests.testAllIntegerValuesAndOutputBudget` (+4) |
| M15 | schema-5 gate making geometry unavailable | AC02 | `PrinterProfileTests.testExplicitMediaGeometryIsValidatedThenRejectedUntilQualified` |
| M17 | pre-schema-7 thermal-transfer rejection | AC01 | `ThermalControlIntegrationTests.testNoImplicitThermalMethodOrUnknownConsumableSubstitutionInNewSchema` (+7) |
| M18 | unknown/unsupported motor speeds may carry choices | AC01 | `MotorSpeedIntegrationTests.testInvalidQualifiedCapabilitiesAndLegacyVersionsFail` |
| M19 | supported motor speeds need evidence | AC01 | `MotorSpeedIntegrationTests.testInvalidQualifiedCapabilitiesAndLegacyVersionsFail` |
| M20 | motor-speed `2...12` declaration range | AC02 | `MotorSpeedIntegrationTests.testInvalidQualifiedCapabilitiesAndLegacyVersionsFail` |
| M21 | positive print-speed-choice declaration | AC02 | `PrinterProfileTests.testProfileRejectsUnsafeIdentityAndImpossibleSpeedObservations` |
| M22 | installed-vs-connection transport consistency | AC02 | `PrinterProfileTests.testProfileCannotSubstituteRawTCPForInstalledUSB` |
| M23 | positive width/length in `MediaGeometryRequest.init` | AC02 | `PrinterProfileTests.testExplicitMediaGeometryIsValidatedThenRejectedUntilQualified` |
| M24 | observed print speed added to the precedence chain | AC01 | `ConfiguredPrinterDefaultsTests.testReadOnlyObservationsNeverBecomeConfiguredDefaults` (+1) |
| M25 | observed darkness added to the precedence chain | AC01 | `ConfiguredPrinterDefaultsTests.testReadOnlyObservationsNeverBecomeConfiguredDefaults` (+1) |
| M26 | observed tracking added to the precedence chain | AC01 | `ConfiguredPrinterDefaultsTests.testReadOnlyObservationsNeverBecomeConfiguredDefaults` (+1) |
| M27 | schema ≥ 7 silently falls back to `.directThermal` | AC01 | `ThermalControlIntegrationTests.testNoImplicitThermalMethodOrUnknownConsumableSubstitutionInNewSchema` |
| M28 | finishing enabled-mode guard | AC01 | `FinishingControlQualificationTests.testEveryModeRequiresIndependentSupportEnabledConfigurationAndExactBytes` |
| M29 | finishing mode needs a supported model fact | AC01 | same as M28 |
| M30 | finishing mode needs model evidence | AC01 | same as M28 |
| M31 | accessory observation needs `reportedInstallation` | AC01 | `FinishingControlQualificationTests.testEachAccessoryNeedsTrueInstallationObservationAndCannotUseModelDocumentation` |
| M32 | absent accessory distinguished from present | AC01 | same as M31 |
| M34 | finishing emitted-byte budget | AC02 | `FinishingControlQualificationTests.testModesRemainOfflineAndDoNotSelectCutIntervalsCopiesOrDestructiveCommands` |
| M35 | thermal method needs a supported model fact | AC01 | `ThermalControlQualificationTests.testEachModelFactIsIndependentAndCannotUseUnobservedSupport` |
| M36 | thermal method needs model evidence | AC01 | same as M35 |
| M37 | loaded-media observation needs `reportedInstallation` | AC01 | `ThermalControlQualificationTests.testDocumentationCannotStandInForLoadedConfigurationAndUnknownIsNotFalse` (+2, incl. `HostObservedEvidenceTests.testAHostObservationCannotSatisfyAnInstallationDeclaration`) |
| M38 | loaded media must match the requested method | AC02 | `ThermalControlQualificationTests.testEachMethodNeedsCompatibleObservedMediaAndRibbonAndProducesExactBytes` |
| M39 | ribbon observation needs `reportedInstallation` | AC01 | `ThermalControlQualificationTests.testDocumentationCannotStandInForLoadedConfigurationAndUnknownIsNotFalse` (+1) |
| M40 | ribbon presence must match the requested method | AC02 | `ThermalControlQualificationTests.testEachMethodNeedsCompatibleObservedMediaAndRibbonAndProducesExactBytes` (+1) |
| M43 | complete-file-delivery needs `reportedInstallation` | AC01 | `FinishingProfilePersistenceTests.testEveryQualifiedFinishingModeResolvesWithoutAdmittingMechanicalEncoding` |
| M44 | absent file boundaries distinguished from present | AC01 | same as M43 |
| M45 | `documentedModel` cannot be substituted by another evidence kind | AC01 | same as M43 |
| M47 | an RFID-capable model is refused | AC02 | same as M43 |
| M48 | declared finishing fact must match the profile capability | AC01 | `FinishingProfilePersistenceTests.testModelInventoryStockAndBatchDeclarationsCannotContradictBoundProfile` |
| M49 | declared accessory installation must match the installed fact | AC01 | same as M48 |
| M50 | an enabled mode needs verified compatible stock | AC01 | same as M48 |
| M51 | batch-schedule declaration bounds | AC02 | same as M48 |
| M52 | offset component needs a supported fact | AC01 | `OffsetControlQualificationTests.testEachQualificationNeedsItsOwnEvidencedRange` |
| M53 | offset model-range membership | AC02 | `OffsetControlQualificationTests.testValuesInsideProtocolButOutsideModelAreRejectedWithoutClamp` |
| M54 | supported offset declaration needs evidence | AC01 | `OffsetControlQualificationTests.testEachQualificationNeedsItsOwnEvidencedRange` |
| M55 | unknown/unsupported offset component may carry a range | AC01 | same as M54 |
| M56 | a black-mark offset requires black-mark tracking | AC02 | `OffsetControlQualificationTests.testBlackMarkRequiresModeOffsetAndSeparateTrackingQualification` (+1) |
| M57 | black-mark tracking needs its own qualified fact | AC01 | same as M56 |
| M58 | black-mark tracking requires an explicit offset (policy layer) | AC02 | same as M56 |
| M59 | empty offset request refused | AC02 | same as M56 |
| M60 | declared offset range inside the documented protocol range | AC02 | `OffsetControlQualificationTests.testEachQualificationNeedsItsOwnEvidencedRange` |
| M61 | half-specified label home refused | AC02 | `PhysicalGeometryQualificationTests.testUnknownAndUnsupportedRequestsRemainDistinct` |
| M62 | continuous tracking requires a length (policy layer) | AC02 | `PhysicalGeometryQualificationTests.testContinuousLengthNeverUsesRetainedModeOrLength` |
| M63 | an explicit length requires continuous tracking | AC02 | same as M62 (+2) |
| M64 | continuous tracking needs a supported capability state | AC01 | same as M62 |
| M65 | continuous tracking needs evidence for that state | AC01 | same as M62 |
| M66 | geometry component needs a supported fact | AC01 | `PhysicalGeometryQualificationTests.testUnknownAndUnsupportedRequestsRemainDistinct` |
| M67 | geometry `minimum...maximum` range check | AC02 | same as M66 (+1) |
| M68 | supported geometry declaration needs evidence | AC01 | `PhysicalGeometryQualificationTests.testDeclarationRequiresEvidenceAndSeparateKnownBounds` |
| M69 | unknown/unsupported geometry component may carry a maximum | AC01 | same as M68 |
| M70 | empty geometry request refused | AC02 | `PhysicalGeometryQualificationTests.testUnknownAndUnsupportedRequestsRemainDistinct` |
| M71 | supported geometry maximum inside `2/1/0...32000` | AC02 | same as M68 |
| M72 | unknown `~HS` support collapses into unsupported | AC01 | `LegacyHostStatusTests.testUnknownUnsupportedAndAbsentNeverManufactureZeroOrHealthy` |
| M73 | a missing status response collapses into unsupported | AC01 | same as M72 |
| M74 | absent serial-number property collapses into unreadable | AC01 | `USBDeviceIdentityQualificationTests.testUnitWithoutSerialNumberDoesNotQualifyAndReportsWhichWayItFailed` |
| M75 | not-unit-distinct placeholder screen | AC02 | same as M74 |
| M76 | bound profile must match the normalization | AC02 | `FinishingProfilePersistenceTests.testEveryQualifiedFinishingModeResolvesWithoutAdmittingMechanicalEncoding` |
| M77 | declared model must match the profile model | AC02 | same as M76 |
| M78 | model-identifier validation | AC02 | same as M76 |
| M80 | adopted identity may carry unobserved evidence | AC01 | `USBDeviceIdentityQualificationTests.testAdoptionRefusesUnobservedEvidenceAndAnUnrepresentableRevision` |
| M81 | enumerated-choice membership in `ProbeOptions` | AC02 | `ProbeOptionsTests.testRejectsUnsupportedValue` |
| M82 | duplicate-key check in `ProbeOptions` | AC02 | `ProbeOptionsTests.testRejectsDuplicate` |
| M83 | unknown option keys passed through instead of omitted | M3-AC12 allowlist, **not** AC02 — see the note after the clause map | `ProbeOptionsTests.testAllowedOnly` (+1) |
| M84 | schema-3 gate on motor-speed qualification | AC02 | `MotorSpeedIntegrationTests.testInvalidQualifiedCapabilitiesAndLegacyVersionsFail` |
| M87 | schema-7 gate on thermal media facts | AC02 | `ThermalProfilePersistenceTests.testConfiguredThermalDefaultsRequireMatchingInstallationObservations` |
| M88 | schema-8 gate on the finishing configuration | AC02 | `FinishingProfilePersistenceTests.testCanonicalRoundTripPreservesEachDeclarationUnknownAndAbsentValue` |
| M89 | schema-2 gate on configured defaults | AC02 | `ConfiguredPrinterDefaultsTests.testDefaultsDoNotAuthorizeUnsupportedOrUnqualifiedControls` |
| M90 | ordinary admission rejects declaration-only schema 8 | AC02 | `FinishingJobTicketTests.testOrdinaryQueueAndTicketRolesStillRejectFinishingProfileEight` (+4) |

### Part 2 — 12 guards survived, what removing each one actually does, and why no test saw it

These twelve mutations produced **zero** test failures on the 346-test baseline.
Two separate questions have to be answered about each, and an earlier revision
of this document answered the second one wrongly for most of them:

1. *Why did no existing test notice?* — for all twelve, because the existing
   assertions demanded only that **something** was thrown, never which error.
   This is the same shape of trap the 2026-09-20 handoff recorded for M2-AC05.
2. *What does removing the guard actually let through?* — this was **not**
   uniform, and was re-derived empirically rather than reasoned about. A probe
   was run under each mutation that exercises exactly the invalid input the new
   tests use and reports whether a value comes back or an error is thrown. On
   the unmutated tree all sixteen probe inputs are rejected with the expected
   error; the table below records what each mutation changed that to.

**The empirical split is 8 / 3 / 1, not 1 / 11.** Eight guards are the only
thing standing between an invalid input and a returned value; three leave a
later check to refuse with a *different* error; one does both depending on the
input. In particular the profile-layer continuous-length and black-mark-offset
guards (M13, M14) are **not** redundant copies of the policy-type rules, as this
document previously claimed: the policy types are only consulted when the
request carries a `mediaGeometry` or `offsets` payload, and the invalid input
here carries neither, so nothing else is ever reached.

| # | Surviving guard | Clause | Removing it | Observed outcome for the invalid input | Why no test saw it |
|---|---|---|---|---|---|
| M11 | `PrinterProfile`: tracking `fact.evidence != .unobserved` | AC01 | **ACCEPTS** | `resolveControls` returns `tracking = .value(.gap)` for a supported-on-paper, `.unobserved` fact | The only profiles requesting tracking in the suite are schema 1 (refused by the schema clause) or hold fully documented facts; this clause never decided an outcome. |
| M12 | `PrinterProfile`: tracking `fact.state == .supported` | AC01 | **ACCEPTS** | returns `.value(.gap)` for both a documented `unsupported` and a documented `unknown` fact | Same. Every unknown fact the suite tried carried `.unobserved` evidence, so the adjacent clause caught it first. |
| M13 | `PrinterProfile`: continuous tracking requires an explicit length | AC02 | **ACCEPTS** | returns `.value(.continuous)` with no label length resolved at all | `PhysicalGeometryQualification` holds a tested copy of the rule, but is only consulted when the request carries a `mediaGeometry`; this one does not, so the copy is never reached. |
| M14 | `PrinterProfile`: black-mark tracking requires an explicit offset | AC02 | **ACCEPTS** | returns `.value(.blackMark)` with no offset resolved at all | Same shape: `OffsetControlQualification`'s copy is only consulted when the request carries an `offsets` payload. |
| M42 | `FinishingOutputQualification`: unknown prepeel refused | AC01 | **ACCEPTS** | returns `ModePolicy.peelPrepeelNotApplicable` — a positive claim about a mechanism nobody observed | The only unknown prepeel fact tested carried `.unobserved` evidence, so `documented()` threw first. |
| M46 | `FinishingOutputQualification`: `supported()` state check | AC01 | **ACCEPTS** | returns `delayedCutSeparateFiles` (documented-`unsupported` `quantityOne`) and `peelExplicitNoPrepeel` (documented-`unsupported` `peelLabelTaken`) | Every "bad" wire fact in the suite was unknown-and-unobserved or `reportedInstallation`, both of which `documented()` rejects. A **documented `unsupported`** fact was never tried. |
| M85 | `PrinterProfile`: schema-5 gate on a physical-geometry declaration | AC02 | **ACCEPTS** | a schema-4 profile is constructed holding a supported 832-dot width declaration | No test stores a well-formed geometry declaration in a pre-schema-5 profile. |
| M86 | `PrinterProfile`: schema-6 gate on an offset declaration | AC02 | **ACCEPTS** | a schema-5 profile is constructed holding a supported `-30...40` shift-left declaration | Same for offsets in a pre-schema-6 profile. |
| M05 | `PrinterProfile`: backfeed capability-state guard | AC01 | rejects differently | `unsupportedBackfeedSpeed(2)` instead of `unavailableBackfeedSpeed(.unknown)` / `(.unsupported)` — the request still fails, but unknown and unsupported collapse into one error, which is the AC01 distinctness itself | `MotorSpeedIntegrationTests` exercises this distinction for **feed** only. |
| M16 | `PrinterProfile`: offsets require schema ≥ 6 | AC02 | rejects differently | `OffsetControlQualification.Error.unavailable(.shiftLeft, .unknown)` instead of `invalidProfileVersion` | `OffsetControlIntegrationTests` asserts only that the schema-1 reference throws, not which error. |
| M41 | `FinishingOutputQualification`: unknown RFID refused | AC01 | rejects differently | `unsupportedRFID` instead of `unavailable(.rfid, .unknown)` — refused, but for the wrong reason: it reports a model known to have RFID, when the truth is that nobody knows | The only unknown RFID fact tested carried `.unobserved` evidence, so `documented()` threw first. |
| M33 | `FinishingControlQualification`: `1...64Ki` output-limit declaration | AC02 | **both** | `maximumOutputBytes: 0` → rejects differently (`outputLimit`, not `invalidOutputLimit`); `maximumOutputBytes: 65537` → **ACCEPTS**, emitting `^MMT` | The suite tried only a zero limit, and only asserted that it threw; no test tried a limit above the bound. |

### Part 3 — the twelve gaps, closed and re-proved

`Packages/LabelCore/Tests/LabelCoreTests/M3ControlQualificationCoverageTests.swift`
adds 8 tests (346 → 354, 0 failures). Every one of the twelve mutations above
was then re-applied against the new suite and byte-restored again. All twelve
now fail, and each is killed by a test that names the exact error rather than
merely asserting that something was thrown.

For the tracking guards the error alone is not enough.
`PrinterProfileError.unavailableTracking` carries the tracking *kind* and not
the capability state, so a test that only checks the refusal cannot tell whether
unsupported, unknown, unevidenced-supported and absent stayed four things — it
would pass just as happily if they had all been normalised into one state.
`testTrackingStateAndEvidenceAreSeparateRequirementsAtTheProfileLayer` therefore
asserts distinctness where it *is* observable, on the facts the constructed
profile retains (three inputs, three retained states, the unevidenced one told
apart from a supported one by its evidence alone, and an absent table entry that
is observably not a stored unknown), **and** that none of the four authorises
the control. Either half failing fails the test. That the profile-layer refusal
is state-erasing is recorded here as an observation for the controller; it is
not a defect this slice changes.

| # | Now killed by | Suite result under the mutation |
|---|---|---|
| M05 | `M3ControlQualificationCoverageTests.testBackfeedUnavailabilityIsReportedApartFromAnUnsupportedChoice` | Executed 354 tests, with 3 failures |
| M11 | `…testTrackingStateAndEvidenceAreSeparateRequirementsAtTheProfileLayer` | Executed 354 tests, with 1 failure |
| M12 | `…testTrackingStateAndEvidenceAreSeparateRequirementsAtTheProfileLayer` | Executed 354 tests, with 2 failures |
| M13 | `…testProfileLayerRequiresALengthWithContinuousAndAnOffsetWithBlackMark` | Executed 354 tests, with 1 failure |
| M14 | `…testProfileLayerRequiresALengthWithContinuousAndAnOffsetWithBlackMark` | Executed 354 tests, with 1 failure |
| M16 | `…testAnOffsetRequestBelowSchemaSixFailsAsAVersionErrorNotAnUnknownRange` | Executed 354 tests, with 1 failure |
| M33 | `…testFinishingOutputLimitDeclarationIsCheckedApartFromTheEmittedBudget` | Executed 354 tests, with 5 failures |
| M41 | `…testADocumentedUnknownWireFactIsRefusedRatherThanReadAsAbsent` | Executed 354 tests, with 1 failure |
| M42 | `…testADocumentedUnknownWireFactIsRefusedRatherThanReadAsAbsent` | Executed 354 tests, with 1 failure |
| M46 | `…testDocumentedUnsupportedWireFactsAreRefusedComponentByComponent` | Executed 354 tests, with 6 failures |
| M85 | `…testQualificationDeclarationsCannotBeStoredBeforeTheirSchemaVersion` | Executed 354 tests, with 1 failure |
| M86 | `…testQualificationDeclarationsCannotBeStoredBeforeTheirSchemaVersion` | Executed 354 tests, with 1 failure |

### Clause-to-test map

**M3-AC01 — "Unknown, absent and unsupported remain distinct":**

- Typed capability states in a profile: M03/M05 → `MotorSpeedIntegrationTests.testUnknownUnsupportedAndIncompleteRemainDistinct`
  and `M3ControlQualificationCoverageTests.testBackfeedUnavailabilityIsReportedApartFromAnUnsupportedChoice`;
  M08/M09 → `DarknessIntegrationTests.testLegacyAndUnqualifiedProfilesRemainUnavailable`;
  M11/M12 → `…testTrackingStateAndEvidenceAreSeparateRequirementsAtTheProfileLayer`,
  which carries the distinctness half of this clause on the retained profile
  facts because `unavailableTracking` does not carry the state (see Part 3).
- Declarations: M18/M19/M54/M55/M68/M69 → `MotorSpeedIntegrationTests.testInvalidQualifiedCapabilitiesAndLegacyVersionsFail`,
  `OffsetControlQualificationTests.testEachQualificationNeedsItsOwnEvidencedRange`,
  `PhysicalGeometryQualificationTests.testDeclarationRequiresEvidenceAndSeparateKnownBounds`.
- Component requests: M52/M64/M65/M66 → `OffsetControlQualificationTests.testEachQualificationNeedsItsOwnEvidencedRange`,
  `PhysicalGeometryQualificationTests.testContinuousLengthNeverUsesRetainedModeOrLength`,
  `…testUnknownAndUnsupportedRequestsRemainDistinct`.
- Wire-boundary facts: M41/M42/M46 → `M3ControlQualificationCoverageTests.testADocumentedUnknownWireFactIsRefusedRatherThanReadAsAbsent`
  and `…testDocumentedUnsupportedWireFactsAreRefusedComponentByComponent`.
- Status and identity readings: M72/M73 → `LegacyHostStatusTests.testUnknownUnsupportedAndAbsentNeverManufactureZeroOrHealthy`;
  M74 → `USBDeviceIdentityQualificationTests.testUnitWithoutSerialNumberDoesNotQualifyAndReportsWhichWayItFailed`.

**M3-AC01 — "unverified accessory controls are not enabled silently":**

- M31/M32 → `FinishingControlQualificationTests.testEachAccessoryNeedsTrueInstallationObservationAndCannotUseModelDocumentation`
  (unobserved, observed-false, observed-with-model-documentation and
  observed-with-unobserved-evidence are all refused, and *absent* is refused as
  its own error rather than as *unverified*).
- M43/M44/M45 → `FinishingProfilePersistenceTests.testEveryQualifiedFinishingModeResolvesWithoutAdmittingMechanicalEncoding`.
- M37/M39 → `HostObservedEvidenceTests.testAHostObservationCannotSatisfyAnInstallationDeclaration`
  (a host observation is not an installation declaration).
- M48/M49/M50 → `FinishingProfilePersistenceTests.testModelInventoryStockAndBatchDeclarationsCannotContradictBoundProfile`.
- M24/M25/M26 → `ConfiguredPrinterDefaultsTests.testReadOnlyObservationsNeverBecomeConfiguredDefaults`
  and `PrinterProfileTests.testObservationsNeitherAuthorizeCommandsNorBreakUnchangedJobs`
  (a read-only observation never enters the precedence chain).

**M3-AC02 — "every explicit choice is range checked":**

- M02/M04/M06/M10/M20/M21/M53/M60/M67/M71/M75/M81 → the rows above, plus
  `M3ControlQualificationCoverageTests.testBackfeedUnavailabilityIsReportedApartFromAnUnsupportedChoice`
  and `…testFinishingOutputLimitDeclarationIsCheckedApartFromTheEmittedBudget`.

**M3-AC02 — "combination checked":**

- M07 (all three motor speeds together), M38/M40 (media and ribbon must match
  the requested thermal method), M56/M58 (black-mark mode ↔ black-mark offset),
  M61 (label home is both coordinates or neither), M62/M63 (continuous mode ↔
  explicit length), M76/M77 (profile and model must match the normalization),
  and — newly — M13/M14 at the profile layer via
  `M3ControlQualificationCoverageTests.testProfileLayerRequiresALengthWithContinuousAndAnOffsetWithBlackMark`.
  M13/M14 are not duplicates of M62/M56: the policy-type rules apply to a
  request that carries a geometry or offset payload, while the profile-layer
  rules are the only thing that refuses a tracking mode selected with **no**
  such payload at all, which the probe in Part 2 confirms by observation.

**M3-AC02 — "fail instead of silently clamping or dropping":**

- `OffsetControlQualificationTests.testValuesInsideProtocolButOutsideModelAreRejectedWithoutClamp`
  is the explicit no-clamp regression (M53); values one step outside the model
  interval, and `Int.min`/`Int.max`, throw rather than saturate.
- Dropping is covered from the other side: M59/M70 (an empty request is refused
  rather than becoming a no-op), and M16/M84/M85/M86/M87/M88/M89/M90 (a control
  or declaration that the profile schema does not admit fails as a version error
  rather than being quietly ignored).

**M83 is deliberately not cited for any M3-AC02 clause.** An earlier revision of
this document listed it under "fail instead of silently clamping or dropping",
which is the opposite of what it shows. `ProbeOptionsTests.testAllowedOnly`
asserts that `parse("ProbeSpeed=3 SecretAddress=private")` **succeeds** and
returns only `["ProbeSpeed": "3"]` — the unknown key is *dropped*, not rejected.
That is an allowlist and privacy property: an arbitrary caller-supplied key
cannot ride into the option dictionary, which belongs with M3-AC12's "options
are validated; logs and IPC do not expose private identities or allow arbitrary
commands", and with the `AGENTS.md` rule against inserting arbitrary strings
into device-facing data. It is evidence *for* that row and **not** evidence that
anything fails-instead-of-dropping. `ProbeOptions`' genuine AC02 range and
combination checks are M81 (a value outside the enumerated choices throws) and
M82 (a duplicate key throws), which are cited above and stay there.

## Artifacts

- New test file: `Packages/LabelCore/Tests/LabelCoreTests/M3ControlQualificationCoverageTests.swift`
- Sources whose guards were mutated and restored (not modified by this slice):
  - `Packages/LabelCore/Sources/LabelCore/PrinterProfile.swift`
  - `Packages/LabelCore/Sources/LabelCore/PrinterControlResolution.swift`
  - `Packages/LabelCore/Sources/LabelCore/FinishingControlQualification.swift`
  - `Packages/LabelCore/Sources/LabelCore/FinishingOutputQualification.swift`
  - `Packages/LabelCore/Sources/LabelCore/FinishingProfileConfiguration.swift`
  - `Packages/LabelCore/Sources/LabelCore/ThermalControlQualification.swift`
  - `Packages/LabelCore/Sources/LabelCore/OffsetControlQualification.swift`
  - `Packages/LabelCore/Sources/LabelCore/PhysicalGeometryQualification.swift`
  - `Packages/LabelCore/Sources/LabelCore/LegacyHostStatus.swift`
  - `Packages/LabelCore/Sources/LabelCore/USBDeviceIdentityQualification.swift`
  - `Packages/LabelCore/Sources/LabelCore/ProbeOptions.swift`
- Pre-existing suites cited above, all under
  `Packages/LabelCore/Tests/LabelCoreTests/`.
- No logs, bitmaps, scanner passes or timings are attached, because nothing was
  rendered, transmitted or printed. The mutation harness itself is a throwaway
  script in a session scratch directory and is not committed; the table above
  is the record of what it did.

## Limitations / next action

This run is level A on a Linux host. It does **not** establish any of the
following, and none of it should be read into a checked box:

1. **Nothing physical was observed.** No GC420d was opened or addressed. That a
   control is refused in portable Swift is not evidence that the printer does
   nothing when a control *is* emitted, and M3-AC10/AC11 remain the rows that
   would need an installed accessory.
2. **The ZPL control encoder trio was deliberately not mutated.**
   `ZPLControlEncoder.swift`, `ZPLDocumentedControlEncoder.swift` and
   `ZPLControlProtocolCoverage.swift` are cited by M3-AC03's live record and are
   out of this slice's file boundary. Their guards are therefore *not* covered
   by this document, and no claim is made about them here. The clause "an
   unqualified control never reaches the wire" is a property of those files as
   much as of the qualification policies, and a separate slice should mutate
   them under M3-AC03.
3. **`Packages/LabelMac` was not built or tested.** It cannot build on Linux.
   Any macOS-side capability reporting, CUPS option validation or IPP attribute
   handling that participates in M3-AC01/AC02 is outside this evidence, and a
   hosted `macos-26` run is the first place it could be compiled at all.
4. **The finishing wire boundary is offline.** `FinishingOutputQualification`
   validates declarations; it emits nothing and observes nothing. A documented
   `unsupported` RFID fact is a statement someone wrote into a fixture.
5. **Mutation coverage is not exhaustive.** 89 guards were mutated across 11
   files. Guards outside those files — JSON codecs, queue and ticket
   definitions, the job-state contracts — were not swept in this slice even
   where they touch the same values. A surviving guard elsewhere would be a
   finding of the same kind.
6. **No ledger record was written and no checkbox was checked.** M3-AC01 and
   M3-AC02 remain unchecked with no record, exactly as they were. This slice is
   source (a new test file is source under `source_is_unchanged`), so it stales
   every existing ledger record; a controller re-seal against the merged result
   must follow, and only that slice may decide whether these two criteria are
   now qualified.

Next action for the controller: after merge, re-seal the stale records, then
decide whether this document plus the cited tests is sufficient to bind M3-AC01
and M3-AC02 at level A — noting limitation 2, which is the largest gap between
what these criteria say and what a portable suite can show.

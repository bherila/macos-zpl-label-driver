# Evidence — M3-AC01 and M3-AC02 control-qualification coverage, proved by mutation

- Date/time and operator: 2026-09-21, automated Claude session, unattended
- Exact repository commit SHA: base `96e33918299fc82a48c5289e4452c39a6f974c37`
  (`origin/main`). Every command below was executed on branch
  `claude/m3-capability-truthfulness-coverage`, which differs from that base in
  exactly three files: this document, the new test file it cites, and the two
  `MANIFEST.sha256` entries covering them. No production source is touched.
  **No ledger record is written by this slice and no acceptance checkbox is
  checked.** This is a source slice; binding a criterion to a merged SHA is a
  separate controller slice against the merged result (see
  `docs/TRACEABILITY.md` and the "Evidence ledger and sequencing" section of
  `AGENTS.md`).
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

Knowing that a guard is uncovered does not say what removing it *does*, nor why
no test noticed. **Those are two questions with two different methods, and
answering the second from the first is what made two previous revisions of this
document wrong.** Both were therefore measured, in two further passes, with
temporary uncommitted scaffolding (deleted before the commit; it asserts
nothing).

*What does removal do* — run the mutation. A probe exercises exactly the invalid
inputs the new tests use and prints, for each, whether a value came back or an
error was thrown and which. Run once on the unmutated tree as a control — all
sixteen probe inputs rejected, with the errors the new tests assert — then once
under each of the twelve mutations:

```sh
swift test --package-path Packages/LabelCore --filter M3ProbeClassificationTests
```

*Why did no existing test notice* — search the suite for the input. Each guard's
refusal was replaced by `fatalError("GUARD-TAKEN-<id>")`, Lane D's own test file
was moved out of the package so only the 346-test baseline ran, and the suite
was executed. A crash proves some existing test fed an input this guard actually
refused, and names the test; a clean `Executed 346 tests, with 0 failures`
proves none did. The compound tracking guard was temporarily split into one
guard per clause so its state and evidence clauses were separately attributable.
For every guard the probe showed was reached, the input the existing suite feeds
was then replayed under the mutation to see whether removal changes the error at
all:

```sh
swift test --package-path Packages/LabelCore --filter M3ProbeExistingInputsTests
```

Both probe passes byte-restored the mutated source and re-checked its SHA-256
after every run. Parts 2a and 2b report the two measurements.
`git status --porcelain` is empty at the commit: both probe files are gone and
every mutation is restored.

Baseline and post-change runs:

```sh
swift test --package-path Packages/LabelCore    # before: Executed 346 tests, with 0 failures
swift test --package-path Packages/LabelCore    # after:  Executed 354 tests, with 0 failures
python3 scripts/check_repo.py
python3 -m unittest discover -s scripts/tests
python3 scripts/run-accelerator-checks.py
python3 scripts/evidence_currency.py
```

`scripts/run-accelerator-checks.py` is required before and after work that
touches a supplied LabelCore source, and this slice adds a LabelCore test file.
An earlier revision of this record omitted it; it was run in both states and
passed in both, reported by the controller rather than the authoring lane:

| State | Revision | Result |
|---|---|---|
| before | `main` at `19474bf` | `PASS: offline accelerator suite.` |
| after | this branch at `f9073bf` | `PASS: offline accelerator suite.` |

Both runs report the same case counts — 132 cross-language round-trips, 180
compression, 12 encoding-benchmark CLI, 15 inert CUPS ABI, 14 inert CUPS filter
ABI and 1 inert filter-to-discard pipeline. That equality is the point: this
slice adds a test file and changes no encoder, oracle or fixture input, so the
accelerator suite is expected to be unmoved, and it is. The suite's own closing
line states its limit, which this record does not widen: macOS, scheduler and
hardware qualification are separate and remain NOT RUN.

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

### Part 2 — 12 guards survived: what removing each one does, and why no test saw it

These twelve mutations produced **zero** test failures on the 346-test baseline.
Two separate questions have to be answered about each, **and they have different
methods**. "What does removal do" is answered by *running the mutation*. "Why did
no existing test notice" is answered by *searching the suite for the input* —
which test, if any, ever fed something this guard refused. Answering the second
question from the first is what produced the errors in the two previous
revisions of this document: a mutation result says nothing about whether an
input was ever supplied, and the two questions are not even about the same
input. Both are now measured, separately, and they do **not** line up row for
row. Part 2a and Part 2b are therefore different tables, and the paragraph
between them explains why a guard can appear in a different bucket in each.

#### Part 2a — what removing the guard does (measured by running the mutation)

A probe was run under each mutation that exercises exactly the invalid input the
new tests use and reports whether a value comes back or an error is thrown. On
the unmutated tree all sixteen probe inputs are rejected with the expected
error; the table records what each mutation changed that to.

**The split is 8 accepted / 3 rejected-differently / 1 both, not 1 / 11.** Eight
guards are the only thing standing between an invalid input and a returned
value; three leave a later check to refuse with a *different* error; one does
both depending on the input. In particular the profile-layer continuous-length
and black-mark-offset guards (M13, M14) are **not** redundant copies of the
policy-type rules *for this input*, as an earlier revision claimed: the policy
types are only consulted when the request carries a `mediaGeometry` or `offsets`
payload, and the input the new tests feed carries neither, so nothing else is
ever reached. (Part 2b shows that for an input which *does* carry a payload the
copies do apply — which is why M13 and M14 land in a different bucket there.)

| # | Surviving guard | Clause | Removing it | Observed outcome for the invalid input |
|---|---|---|---|---|
| M11 | `PrinterProfile`: tracking `fact.evidence != .unobserved` | AC01 | **ACCEPTS** | `resolveControls` returns `tracking = .value(.gap)` for a supported-on-paper, `.unobserved` fact |
| M12 | `PrinterProfile`: tracking `fact.state == .supported` | AC01 | **ACCEPTS** | returns `.value(.gap)` for both a documented `unsupported` and a documented `unknown` fact |
| M13 | `PrinterProfile`: continuous tracking requires an explicit length | AC02 | **ACCEPTS** | returns `.value(.continuous)` with no label length resolved at all |
| M14 | `PrinterProfile`: black-mark tracking requires an explicit offset | AC02 | **ACCEPTS** | returns `.value(.blackMark)` with no offset resolved at all |
| M42 | `FinishingOutputQualification`: unknown prepeel refused | AC01 | **ACCEPTS** | returns `ModePolicy.peelPrepeelNotApplicable` — a positive claim about a mechanism nobody observed |
| M46 | `FinishingOutputQualification`: `supported()` state check | AC01 | **ACCEPTS** | returns `delayedCutSeparateFiles` (documented-`unsupported` `quantityOne`) and `peelExplicitNoPrepeel` (documented-`unsupported` `peelLabelTaken`) |
| M85 | `PrinterProfile`: schema-5 gate on a physical-geometry declaration | AC02 | **ACCEPTS** | a schema-4 profile is constructed holding a supported 832-dot width declaration |
| M86 | `PrinterProfile`: schema-6 gate on an offset declaration | AC02 | **ACCEPTS** | a schema-5 profile is constructed holding a supported `-30...40` shift-left declaration |
| M05 | `PrinterProfile`: backfeed capability-state guard | AC01 | rejects differently | `unsupportedBackfeedSpeed(2)` instead of `unavailableBackfeedSpeed(.unknown)` / `(.unsupported)` — the request still fails, but unknown and unsupported collapse into one error, which is the AC01 distinctness itself |
| M16 | `PrinterProfile`: offsets require schema ≥ 6 | AC02 | rejects differently | `OffsetControlQualification.Error.unavailable(.shiftLeft, .unknown)` instead of `invalidProfileVersion` |
| M41 | `FinishingOutputQualification`: unknown RFID refused | AC01 | rejects differently | `unsupportedRFID` instead of `unavailable(.rfid, .unknown)` — refused, but for the wrong reason: it reports a model known to have RFID, when the truth is that nobody knows |
| M33 | `FinishingControlQualification`: `1...64Ki` output-limit declaration | AC02 | **both** | `maximumOutputBytes: 0` → rejects differently (`outputLimit`, not `invalidOutputLimit`); `maximumOutputBytes: 65537` → **ACCEPTS**, emitting `^MMT` |

#### Part 2b — why no existing test noticed (measured by searching the suite)

A mutation result cannot answer this, and the first two revisions of this
document tried to. What answers it is whether any pre-existing test ever fed
this guard something it refused. That was established by a **reachability
probe**: each guard's refusal was temporarily replaced by
`fatalError("GUARD-TAKEN-<id>")`, Lane D's own test file was moved out of the
package so only the 346-test baseline ran, and the suite was executed. A crash
means some existing test fed an input this guard actually rejected, and the
output names the test that was running; a clean `Executed 346 tests, with 0
failures` means none did. The compound tracking guard was temporarily split into
one guard per clause so the state and evidence clauses were separately
attributable. For the guards that *were* reached, the input the existing suite
feeds was then replayed under the mutation to see whether removal changes the
error at all.

Three causes, not two:

- **A — input absent.** No existing test ever made this guard refuse anything.
  A bare `XCTAssertThrowsError` could not have caught the removal because the
  input was never supplied. This is the cause the 2026-09-20 handoff recorded
  for M2-AC05, and it is worth being exact about which cause that was, because
  this document previously cited it loosely for all twelve guards here.
  `docs/PROGRESS.json` describes it as: "the obvious place to look,
  `WorkerBitmapBindingTests.swift`, does not cover the guard: it holds one test
  for dimension and allocation bounds **whose positive case still passes without
  it**." A positive case that still passes is an input that never reached the
  refusal, which reads as cause A rather than a weakly-asserted negative case.
  **That is a reading of another record, not a measurement made here**: the
  guard is in `Packages/LabelMac`, which cannot be built or run on this host, so
  nothing in this document re-establishes it and the classification of M2-AC05
  is not evidence for anything in the tables below. The lesson it carries ("do
  not assume the obviously-named test covers what it is named after") is what
  motivated this sweep, and it applies to all three causes.
- **B1 — exercised, error unnamed, removal changes the error.** The input was
  fed, the guard did refuse it, and removal shifts the refusal to a different
  error. Naming the error in the existing assertion **would** have caught it.
- **B2 — exercised, error unnamed, removal throws the identical error.** The
  input was fed, but it carries a payload that makes a policy-type copy of the
  rule apply, and that copy throws the *same* error case. Naming the error would
  **not** have caught it; only a different input would.

| # | Cause | How established |
|---|---|---|
| M05 | **A** | `fatalError` at the backfeed state guard never fired, suite completed `Executed 346 tests, with 0 failures`. Instrumenting the backfeed block to print on every *entry* rather than only on refusal shows why: it is entered 33 times, at speeds 2, 3, 4 and 12, and the backfeed capability is `state: .supported` on **every** one of them, so the state guard is always satisfied and any refusal comes from the membership check instead. No existing test pairs a non-supported backfeed capability with a request that reaches this block. |
| M11 | **A** | Tracking guard split per clause; `fatalError` on the evidence clause never fired, suite completed 346/0. **Reached is not the same as refused, and an earlier revision of this row explained the silence with a false inventory** — it said every pre-existing tracking request is schema 1–2 or schema 5–6, omitting the schema-7 (`ThermalControlTestFixture.profile`) and schema-8 (`FinishingProfilePersistenceTests`) paths. Instrumenting the clauses to print on every *evaluation* rather than only on refusal settles it: they are evaluated **177 times, at schemas 5, 6, 7 and 8**, for continuous, black-mark and gap, and every one of those requests passes both clauses because every fact reaching them is `state: .supported` carrying `documentedModel` evidence. So the schema-7 and schema-8 requests do reach these clauses and satisfy them — including the black-mark request in `testOfflineFinishingResolutionSharesEffectiveControlValidationAndKeepsOrdinaryGate`, which necessarily passes them before reaching the M14 refusal. What no existing test ever supplies is the *refusing* combination: a non-supported or unevidenced fact at a schema that admits tracking at all. |
| M12 | **A** | Same probe and same instrumentation: the state clause is evaluated on all 177 of those requests and satisfied by every one, so it never refuses. |
| M85 | **A** | `fatalError` at the schema-5 declaration gate never fired, suite completed 346/0. Instrumented to print schema and whether a declaration is present on every evaluation, the gate is evaluated 488 times: `PrinterProfile.init` **is** reached with schemas 1–4, 320 times, but always with no geometry declaration, and a declaration first appears at schema 5. So the initialiser is never reached with the refusing combination. (An earlier revision attributed that to the codec rejecting the schema-mutated JSON first. That mechanism was not measured and is not claimed here; what is measured is that the pair never arrives.) |
| M86 | **A** | Same instrumentation for the schema-6 offset declaration gate: 488 evaluations, declarations present only at schemas 6, 7 and 8, never below, so it too is never reached with the refusing combination. |
| M33 | **A + B1** | `fatalError` at the limit bound **was** reached, by `FinishingControlQualificationTests.testModesRemainOfflineAndDoNotSelectCutIntervalsCopiesOrDestructiveCommands` — the `maximumOutputBytes: 0` case, asserted with a bare `XCTAssertThrowsError`; replayed under the mutation it becomes `outputLimit` instead of `invalidOutputLimit`, so that half is **B1**. The above-bound half is **A**: no existing test passes a limit greater than 64 KiB. |
| M16 | **B1** | `fatalError` reached in `OffsetControlIntegrationTests.testBlackMarkMappingRequiresQualifiedOffsetAndRejectsIncompatibleLength`. Replayed: `invalidProfileVersion` → `unavailable(.shiftLeft, .unknown)`. |
| M41 | **B1** | `fatalError` reached in `FinishingProfilePersistenceTests.testEveryQualifiedFinishingModeResolvesWithoutAdmittingMechanicalEncoding`. Replayed: `unavailable(.rfid, .unknown)` → `missingModelEvidence(.rfid)`. |
| M42 | **B1** | Same test. Replayed: `unavailable(.prepeel, .unknown)` → `missingModelEvidence(.prepeel)`. |
| M46 | **B1** | Same test. Replayed: `unavailable(.quantityOne, .unknown)` → `missingModelEvidence(.quantityOne)`. |
| M13 | **B2** | `fatalError` reached in `GeometryControlIntegrationTests.testConflictingModeAndLengthCannotBeSilentlyDropped`. That input selects continuous tracking against a profile whose configured defaults already carry a `mediaGeometry`, so replayed under the mutation `PhysicalGeometryQualification` throws the **identical** `continuousLengthRequired`. |
| M14 | **B2** | `fatalError` reached in `FinishingProfilePersistenceTests.testOfflineFinishingResolutionSharesEffectiveControlValidationAndKeepsOrdinaryGate`. That input selects black-mark tracking against a profile whose configured defaults already carry an `offsets` payload, so replayed under the mutation `OffsetControlQualification` throws the **identical** `blackMarkOffsetRequired`. |

**Counts: A = 5, B1 = 4, B2 = 2, and M33 in both A and B1.**

##### Why 2a and 2b do not line up, and four corrections that follow

The two tables are about **different inputs**, so a guard can accept in 2a and
be reached in 2b without contradiction. M42 and M46 are the clearest case: the
existing suite feeds an unknown-and-`.unobserved` fact, which the guard refuses
and whose removal merely changes the error (B1); the new tests feed a
*documented* unknown or unsupported fact, which removal **accepts** (2a). The
guard is the only thing refusing the second input, and only the first was ever
tried. M13 and M14 are the mirror image: reached on an input that carries a
payload, where a policy copy still refuses identically (B2), but accepting on
the payload-free input the new tests feed.

Four claims in earlier revisions of this document were wrong and are corrected
here:

1. "For all twelve, the assertions demanded only that something was thrown."
   False for the five cause-A guards: those inputs were never supplied, so no
   assertion of any strength could have caught the removal. This was the
   finding under review.
2. The rows for M41, M42 and M46 said `documented()` "threw first" for the
   existing unknown-state facts. That is the wrong order:
   `guard rfid.state != .unknown`, `guard prepeel.state != .unknown` and
   `supported()`'s state check all run **before** `documented()`, and the
   reachability probe confirms they are the clauses that actually refuse those
   inputs. The reason no test noticed is that the assertions did not name the
   error, not that another clause got there first.
3. M13 and M14 were placed in the absent bucket on the reasoning that the
   policy types hold tested copies. Measured, they are reached: the copies do
   apply to the inputs the existing suite feeds, and throw the same error case,
   which is why removal was invisible there.
4. The cause-A rows for M05, M11, M12 and M85 supported a true measurement with
   an untrue or unmeasured explanation of it. M11/M12 claimed an inventory of
   pre-existing tracking requests that omitted the schema-7 and schema-8 paths;
   M05 called a single request the only one reaching the backfeed block, where
   there are 33; M85 asserted a codec mechanism nobody had measured. All four
   are now instrumented counts. A false supporting claim under a sound
   measurement is worse than none, because it invites a reader to trust the
   reasoning instead of the probe — which is exactly the failure mode the note
   at the head of Part 2 is about.

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

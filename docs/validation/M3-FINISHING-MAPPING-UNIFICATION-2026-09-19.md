# One authoritative finishing-mode literal table — 2026-09-19

Partial M3 protocol-mapping software only. No installed queue, scheduler
admission, device I/O, transport, calibration, privileged action or physical
output. Nothing here claims an acceptance criterion; the ledger is not touched.

Issue #103 observed that the ZPL finishing control mapping had a literal
restated at every site that emits one, and that only the LabelCore site is
covered by tests that execute on this host. This slice makes
`ZPLFinishingControlLiteral`, added to
`Packages/LabelCore/Sources/LabelCore/ZPLControlProtocolCoverage.swift`, the one
place the literals are written down. Every emitting site now derives from it,
including the production framing in
`Packages/LabelMac/Sources/LabelMac/FinishingFramedOutput.swift`, and the
`qualifiedFinishingControls` coverage rows derive their `command` field from the
same table rather than restating it.

## Site-by-site literal comparison, before this slice

| Site | Package | Route | Literals emitted |
|---|---|---|---|
| `FinishingControlQualification.encodeMode` | LabelCore | Bounded offline inspection | `^MMT`, `^MMC`, `^MMP`, `^MMR` |
| `FinishingFramedOutput.prepare` | LabelMac | Production framed output | `^MMT`, `^MMR`, `^MMP,N`, `^MMP`, `^MMD`, and `~JK` as a separate trigger file |
| `ZPLControlEncoder.encode` | LabelCore | Ordinary control fragment | `^MMT` |
| `ZPLDocumentedControlEncoder.encode` | LabelCore | Documented control fragment | `^MMT` |
| `ZPLControlProtocol.qualifiedFinishingControls` | LabelCore | Coverage metadata (emits nothing) | `^MMT`, `^MMC/^MMD/~JK`, `^MMP,N/^MMP`, `^MMR` |

Per finishing mode, where the two emitting routes disagree:

| `FinishingMode` | Offline inspection | Production framing | Coverage row |
|---|---|---|---|
| `.tearOff` | `^MMT` | `^MMT` | `^MMT` |
| `.cut` | `^MMC` | `^MMD` plus a later `~JK` trigger file | `^MMC/^MMD/~JK` |
| `.peel` | `^MMP` | `^MMP,N` when prepeel is qualified, otherwise `^MMP` | `^MMP,N/^MMP` |
| `.rewind` | `^MMR` | `^MMR` | `^MMR` |

### Finding: the divergence is benign, and is not what issue #103 is about

The two routes differ for `.cut` and `.peel`, but **both differences are
deliberate, documented and correct**, and no fix was warranted:

- `.cut`: `^MMC` alone selects a cut mode without expressing a per-label, batch
  or job-end policy, so the offline route says so in its own comment and emits
  no trigger. The production route uses the separately qualified delayed-cut
  mode `^MMD` and a `~JK` trigger in its own later file, after observed
  readiness. Substituting one for the other in either direction would be a
  correctness regression, not a unification.
- `.peel`: the offline route encodes a mode fragment and has no prepeel fact to
  read. The production route has one and selects `^MMP,N` only when prepeel is
  explicitly qualified. The offline `^MMP` is the same literal the production
  route uses for `.peelPrepeelNotApplicable`.

Every literal either route emits was already listed in the coverage rows, so
**no byte sequence changed in this slice and no divergence bug was found.** The
drift issue #103 names is not a byte divergence: it is that the production
route's literals live in LabelMac, which does not build on Linux, so nothing
executed could catch a regression in them, and the restatement at each site is
what let the two sites be maintained independently in the first place.

## What this slice changes

`ZPLFinishingControlLiteral` is a `String`-raw-valued, `CaseIterable` enum whose
seven cases are `^MMT`, `^MMC`, `^MMD`, `^MMP`, `^MMP,N`, `^MMR` and `~JK`. Its
`line` property is the only way a literal becomes bytes, and nothing is
interpolated into it: no profile string and no document content reaches these
commands. Three derivations are exposed and each keeps the two routes distinct
rather than merging them:

- `offlineInspection(of:)` — the bounded offline route; it can never return
  `.delayedCut` or `.delayedCutTrigger`.
- `framedMode(of:)` — the production route, keyed on
  `FinishingOutputQualification.ModePolicy`; it can never return
  `.immediateCut`.
- `documented(of:)` / `documentedCommand(of:)` — the coverage rows, derived.

Membership in the table grants nothing. It is protocol mapping only: no model
support, no accessory presence, no readiness, no completion and no authority to
reach a device. Every emitting site keeps the capability gate it already had.

## Preserved exactly

Verified by reading the diff; `FinishingFramedOutput.prepare` changed only where
the two `Data(...)` literals were constructed.

- The capability gate `try qualification.validate(preparation.normalization)`
  still runs before any mode byte exists, and the raster binding validation
  still runs after it and before any format is built. `~JK` is still produced
  only inside the `cuts.contains(ordinal)` branch, i.e. only for a plan whose
  qualified policy is `delayedCutSeparateFiles`.
- Delayed-cut framing and ordering: `.formatFile`, `.awaitLabelPrinted`, then
  `.awaitDelayedCutReady`, `.delayedCutFile`, `.awaitCutCompleted`, then
  `.awaitLabelTaken` for peel. Unchanged, and still asserted step-for-step by
  `ProfileBoundFinishingJobPlanTests`.
- Cancellation and the deadline: the `check()` closure and its call sites are
  untouched.
- Uncertain publication and no automatic replay: untouched. This slice adds no
  send, no retry and no completion inference; `FinishingOutputStep` still
  describes requirements for a future qualified sender, not receipts.
- Raw ZPL pass-through: untouched, and still not reachable from this path.
- `^PQ1`, `^XA`/`^XZ` framing, the byte budget, the overflow-checked arithmetic
  and every typed error: unchanged.
- Offline inspection still emits `^MMC` and still emits no `~JK`.

## Regression tests added

`ZPLControlProtocolCoverageTests` (LabelCore, executes on this host):

- `testFinishingLiteralTableIsAuthoritativeForEveryEmittingRoute` pins all seven
  raw values and their `line` bytes, pins the offline route's four literals,
  pins **the production route's five policy literals and the `~JK` trigger**,
  asserts the offline route never reaches the delayed-cut literals and the
  production route never reaches `^MMC`, asserts every coverage row's `command`
  equals the derived string, and asserts the documented mapping covers every
  case in the enum. This is the part that matters for issue #103: the production
  framing's literals are now pinned by a test that runs where LabelMac cannot
  build.
- `testNoEmittingSourceRestatesAFinishingLiteral` reads the five emitting source
  files from disk — including the LabelMac one — strips `//` comments so prose
  may still cite a command, and fails naming the file, line and literal if code
  restates one. A missing file fails rather than skipping. It also asserts the
  table itself still spells every literal out.

`ProfileBoundFinishingJobPlanTests` (LabelMac, NOT executed here): the existing
hardcoded `modeText` oracle is kept as an independent restatement and is now
additionally asserted equal to `ZPLFinishingControlLiteral.framedMode(of:).line`;
each format file is asserted to contain no finishing literal other than the one
its qualified policy selected; and the `~JK` trigger bytes are asserted against
the table. No existing assertion was weakened, skipped or removed.

### Deliberate fault injected to prove the guard bites

`FinishingFramedOutput.prepare`'s derived mode was temporarily replaced with a
restated `Data("^MMD\n".utf8)` and the LabelCore suite was re-run:

```
ZPLControlProtocolCoverageTests.testNoEmittingSourceRestatesAFinishingLiteral : failed -
Packages/LabelMac/Sources/LabelMac/FinishingFramedOutput.swift:53 restates ^MMD;
derive it from ZPLFinishingControlLiteral instead
```

Executed 4 tests, with 1 failure. The source was restored and the suite returned
to 0 failures. A re-hardcoded literal in LabelMac is therefore caught by a test
that runs on Linux.

## Environment

Linux x86_64 (`Linux 6.18.44-fc-v37`), Swift 6.1.3
(`swift-6.1.3-RELEASE`, `x86_64-unknown-linux-gnu`), Python 3.11.15. Worktree
`/home/user/wt-t1-finishing`, branch `codex/m3-t1-finishing`, based on
`origin/main` `eb70ca7`.

`Packages/LabelMac` declares `platforms: [.macOS("26.0")]` and imports
CryptoKit, Darwin and CoreGraphics. It cannot be compiled or type-checked on
this host. Hosted `macos-26` CI is the first real compile of the LabelMac
changes in this slice.

## Commands and exact results

| Command | Result |
|---|---|
| `python3 scripts/check_repo.py` | exit 0 — "Repository preflight passed (links, metadata, milestone files, action pins)." |
| `python3 -m unittest discover -s scripts/tests` | exit 0 — Ran 161 tests, OK (skipped=2) |
| `swift test --package-path Packages/LabelCore` | exit 0 — Executed 328 tests, 0 failures (326 before this slice; 2 new) |
| `swift test --package-path Packages/LabelCore --configuration release` | exit 0 — Executed 328 tests, 0 failures |
| `python3 scripts/run-accelerator-checks.py` | exit 0 — "PASS: offline accelerator suite"; 132 cross-language round-trips, 180 ASCII round-trips, 12 benchmark cases, 15 inert CUPS ABI, 14 filter ABI, 1 discard-pipeline case |
| `git diff --check` | exit 0, no output |
| `swiftc -frontend -parse` on each of the 7 changed Swift files | exit 0 each — syntax only, **not** type checking |
| `python3 scripts/evidence_currency.py` | exit 0 — read-only, non-gating. Same 11 CLAIMED-WITHOUT-RECORD rows as before the slice, plus STALE-SOURCE on M2-AC04 and M2-AC13. `source_is_unchanged` is repository-wide, so any slice that touches a source file stales every previously qualified record until the controller re-seals; neither row binds a file this slice touches |
| `python3 scripts/manifest_audit.py` | exit 0 — 0 stale digests, 0 absent paths, 0 untracked entries, 0 oversized entries |
| `sha256sum -c MANIFEST.sha256` | exit 0, all entries OK |

`Packages/LabelCore/Sources/LabelCore/ZPLControlEncoder.swift` is the only file
this slice touches that the manifest already covers; its digest was re-hashed in
place. No manifest entry was added or removed.

## NOT RUN

- `swift test --package-path Packages/LabelMac` — NOT RUN. LabelMac is
  macOS-26-only and cannot build on this Linux host. The LabelMac source and
  test changes in this slice are **unverified by any compiler**;
  `swiftc -frontend -parse` proved syntax only.
- `swift build --package-path Packages/LabelMac` — NOT RUN, same reason.
- `bash scripts/ci-swift.sh` — NOT RUN. It requires a Mac.
- Any type check of `ZPLFinishingControlLiteral`'s use from LabelMac — NOT RUN.
- GUI, Core Graphics, Quartz rendering, signing, installer and USB paths — NOT
  RUN and not touched.
- Any printer I/O, connection, calibration, firmware action, scheduler
  interaction or privileged operation — NOT RUN, and none is reachable from this
  slice.
- Physical printing on the GC420d, and any observation of real cutter, peeler or
  rewinder behaviour — NOT RUN. This slice is protocol mapping. It establishes
  nothing about a physical device and does not narrow M3-AC10.
- No acceptance criterion is claimed. `docs/ACCEPTANCE-EVIDENCE.json`,
  `docs/PROGRESS.json`, `docs/HANDOFF.md` and every
  `docs/milestones/*/ACCEPTANCE.md` are untouched; re-sealing and any M3-AC03
  decision belong to the controller, and still require the hosted macOS run that
  issue #103 describes.

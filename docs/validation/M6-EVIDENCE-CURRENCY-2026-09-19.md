# Evidence — acceptance-currency diagnostic and manifest coverage investigation

- Date/time and operator: 2026-09-19, automated Claude session, unattended
- Exact repository commit SHA: `da05bb8ca9822afcf852c06aa9309bbb0d99bc56` on
  `codex/m6-evidence-currency`, based on `main` at
  `d6f03d75e48baef4a9afb10333f2d73987cf93ff`. `main` advanced to
  `c3bbc5c9a7a024cdb3718ac0a9f9fe8fd80ebc05` (#111) while this slice was in progress; the
  branch is deliberately not rebased, and the merge is verified below rather than assumed.
- Related requirement and acceptance IDs: **none claimed**. This slice records no
  assessment, checks no box and advances no acceptance row. M6-AC01 (traceability)
  is the criterion this tooling serves; it remains unrecorded.
- Evidence level: A for the tooling's own regressions. Nothing here is C, I, H or R.
- Status: PASS for the commands below, on the boundary stated under Limitations
- macOS/Linux, architecture, Swift, Xcode/SDK, runner image (as applicable):
  Linux x86_64 (`x86_64-unknown-linux-gnu`), Swift 6.1.3 release toolchain,
  CPython 3.11, git 2.x, `libcups2-dev` present. No macOS, no Xcode, no runner
  image, no hosted Actions run.
- Application/version and system-dialog versus browser-preview path: none. No
  application, dialog or browser path is exercised.
- Printer model, resolution, firmware family, transport, stock/accessories (no serial):
  none. No printer, transport or device command.
- Fixture ID/hash and generator version: no committed fixture is used. The new
  Python tests build synthetic git repositories in temporary directories and
  delete them.
- Profile/job-ticket revision/hash: none read or written.
- Explicit hardware/installation authorization and finite label/command budget:
  not required and not requested. Zero labels, zero device commands, zero system
  changes.

## Procedure

Three problems, one slice.

**1. Four questions were answered as one.** `build_report` computed
`meetsRequiredDeclaredEvidence` as a conjunction of four independent facts, so a row
could not be distinguished from a qualified one by anything the report printed. The four
are now separate fields on each row's `evidenceStatus`:

| Field | Question |
|---|---|
| `checkboxComplete` | is the box checked in the milestone `ACCEPTANCE.md`? |
| `hasDigestValidRecord` | do a passing record's cited bytes still hash to its recorded digest? |
| `hasCurrentSourceRecord` | does a passing record's evaluated source still describe HEAD? |
| `hasRequiredLevelRecord` | is a passing record at the level `docs/VALIDATION-PLAN.md` prescribes? |

The booleans diagnose; they never qualify. Each may be answered by a *different* record,
so `qualified` still requires one single record to answer all four at once — which is
`meetsRequiredDeclaredEvidence` on that record, plus a checked box and no current
blocker. `test_dimension_booleans_never_qualify_a_row_by_themselves` builds exactly that
trap: a stale A record and a current C record on an A row, where all three dimension
booleans read true and the verdict is still `stale-source`.

`promotesBelowRequiredLevel` is set when a row prescribing I, H or R carries a passing A
or C record. `verdict` names the first unanswered question of the record answering the
most of them, from a fixed nine-word vocabulary, and `evidenceSummary` counts every row
exactly once.

**2. Nothing read the currency field.** `docs/HANDOFF.md` records the request directly:
"a check that fails when main carries a record whose currentSource is false would turn a
silent dip into a visible one, and the report already computes that field".
`scripts/evidence_currency.py` is that check.

**3. Issue #87.** `scripts/manifest_audit.py` measures manifest coverage; the policy
investigation is below and in [ADR 0004](../adr/0004-manifest-integrity-scope.md).

### Gate or report, and why

The diagnostic has exactly three outcomes and no skip: exit 0 clean, exit 1 gating
finding, exit 2 could not evaluate. AGENTS.md is explicit that a missing required check
is a failure rather than a successful conditional skip, so every unevaluable input is
exit 2 — an absent, empty or malformed `MANIFEST.sha256`, an unreadable or misshapen
ledger, a directory without git history, an exhausted report deadline, or a workspace
that changes while the diagnostic runs. There is no path on which the diagnostic prints
nothing and returns 0.

Findings are split deliberately:

- **Gating**, because they are wrong regardless of sequencing: `MISSING-BINDING` (a
  record with an empty `implementation` or `evidence` list binds no bytes),
  `INVALID-REFERENCES` (the ledger cites bytes that no longer match — the ledger is
  wrong, not the tree), `WRONG-EVIDENCE-LEVEL`, `LEVEL-PROMOTION` (an I/H/R row offered
  a passing A or C record) and `CURRENT-BLOCKER`.
- **Reported**, not gating by default: `STALE-SOURCE`. This is the deliberate choice and
  the argued one. A source slice *necessarily* makes every record stale — that is the
  repository's own recorded sequencing rule, that a record written in the same commit as
  its source cannot bind that commit — so gating staleness in the `repository-preflight`
  job would fail the very pull request doing the work, and the cheapest way to green
  would be deleting records. AGENTS.md forbids silently lowering acceptance criteria to
  obtain a green build, and a gate whose easiest fix is deleting evidence is that
  pressure by construction. The check therefore always evaluates and always prints the
  verdict; only the gate is scoped. `--gate-stale` turns it into a failure and is what a
  main-push gate would enable once the maintainer accepts a red `main` between a source
  PR and its evidence PR. It is left off here because this slice itself would turn `main`
  red on merge, for the reason measured below.
- **Reported**, because the fix is a human's acceptance claim: `CLAIMED-WITHOUT-RECORD`,
  `NO-PASSING-RECORD`, `RECORD-WITHOUT-CHECKBOX`, `WORKSPACE-DIRTY`. These name
  `ACCEPTANCE.md` boxes, which this slice does not own and does not touch.

### Commands actually run

All at `da05bb8`, Swift 6.1.3 on `PATH`, Linux x86_64:

```sh
python3 scripts/check_repo.py                      # exit 0
python3 -m unittest discover -s scripts/tests      # exit 0
python3 scripts/traceability_report.py             # exit 0
python3 scripts/evidence_currency.py               # exit 0
python3 scripts/manifest_audit.py                  # exit 0
swift test --package-path Packages/LabelCore       # exit 0
python3 scripts/run-accelerator-checks.py          # exit 0
git diff --check                                   # exit 0
python3 -c "import yaml; yaml.safe_load(...)"      # exit 0, both workflows
```

## Expected and observed results

`python3 -m unittest discover -s scripts/tests` reports **144 tests, OK (skipped=2)**, up
from 108 before this slice: 17 in `test_evidence_currency.py`, 13 in
`test_manifest_audit.py`, and 6 added to `test_traceability_report.py`.

`swift test --package-path Packages/LabelCore` reports **313 tests, 0 failures**,
unchanged, because no Swift file is touched.

`python3 scripts/run-accelerator-checks.py` passed end to end:

```
Executed 313 tests, with 0 failures (0 unexpected) in 4.952 seconds
Cross-language ZPL/PBM/analytic round-trips: 132
Independent ASCII compression round-trips: 180
Finite encoding benchmark CLI cases: 12
Inert CUPS ABI cases: 15
Inert CUPS filter ABI cases: 14
Inert filter-to-discard pipeline cases: 1
PASS: offline accelerator suite. macOS/scheduler/hardware qualification is separate.
```

`python3 scripts/check_repo.py` passed. `git diff --check` reported nothing. Both
workflow files parse under PyYAML; `repository-preflight` now has five steps and the new
two are read-only invocations placed between `Validate repository` and `Classify change
scope`.

The workflow change was checked against the **merged** `ci.yml`, not the base one. #111
added two steps at the end of the `macos` job, both gated on
`if: success() && github.event_name == 'push' && github.ref == 'refs/heads/main'`; this
slice adds two steps to the `repository` job, so the two touch disjoint regions.
`git merge-tree --write-tree HEAD origin/main` produced a tree with **zero conflict
markers**, and `ci.yml` in that tree parses under PyYAML with all three jobs and both sets
of steps present:

```
repository  checkout, Validate repository, Acceptance evidence currency,
            Manifest coverage measurement, Classify change scope
macos       checkout, Identify Swift cache toolchain, Restore Swift build cache,
            Native Swift build tests and local-signature smoke, Save Swift build cache
            from main, Retain short-lived diagnostic log,
            Package tested local-ad-hoc app from main, Upload tested local-ad-hoc app
required    Check all required results
```

This slice therefore has no dependency on #111 and no conflict with it.

`python3 scripts/evidence_currency.py` at `da05bb8`, on a clean worktree, exit 0. The four
counts it prints are **identical to the `c3bbc5c` figures above** — 13 / 2 / 0 / 2, with 11
checked-and-unrecorded and 0 qualified — because #111 changed no acceptance input, which is
an independent reproduction of the controller's measurement from a different base:

```
  ID        need  a  b  c  d   verdict
  M2-AC02   A     x  .  .  .   claimed-without-record
  M2-AC04   A     x  x  .  x   stale-source
  M2-AC09   A     x  .  .  .   claimed-without-record
  M2-AC12   I     x  .  .  .   claimed-without-record
  M2-AC13   A     x  x  .  x   stale-source
  ... eight further A rows, all claimed-without-record

All 90 rows by verdict:
     2  stale-source
    11  claimed-without-record
    77  no-record
```

Two findings are worth the maintainer's attention and are **reported, not acted on**:

1. **Eleven checked boxes have no ledger record at all** — M2-AC02, M2-AC09, M2-AC12,
   M4-AC02, M4-AC03, M4-AC04, M4-AC05, M4-AC07, M4-AC08, M4-AC13 and M5-AC12. Before this
   slice the report showed `declaredComplete: true` with an empty `records` list, which
   is easy to read past; it now reads `claimed-without-record` and is counted in the
   summary. This is the same population `docs/validation/M0-ACCEPTANCE-LEDGER-2026-09-18.md`
   listed as "declared complete; no current evidence record", so the finding is a
   restatement of a known state, not a new defect. Nine similar claims were unchecked by
   #102; these eleven were not.
2. **M2-AC12 is an I-level row among them.** A checked box on a criterion prescribing
   macOS-integration evidence, with nothing recorded, is exactly the shape AGENTS.md
   warns about. Correcting it means either recording I evidence from a Mac or unchecking
   the box, both of which edit files this slice does not own. It is reported here rather
   than edited.

`python3 scripts/manifest_audit.py` at `da05bb8`: 355 entries over 498 tracked files, 142
omitted, 0 stale digests, 0 absent paths, 0 untracked entries.

### Worked example: `main` at `c3bbc5c`, measured not hypothesised

This slice was written against `main` at `d6f03d7`. While it was in progress #111 merged,
giving `main` at `c3bbc5c9a7a024cdb3718ac0a9f9fe8fd80ebc05`, and the controller ran
`python3 scripts/traceability_report.py` there in a throwaway worktree. `.github/` is not
an exempt path in `source_is_unchanged`, so that merge staled both records:

```
sourceSHA           c3bbc5c9a7a024cdb3718ac0a9f9fe8fd80ebc05
workspaceDirty      False
acceptance rows     90
requirements        0 of 21 satisfied
declaredComplete    13 ids
rows with records    2 ids: M2-AC04, M2-AC13
hasCurrentDeclaredPass  [] (empty)
  M2-AC04  level A  referencesValid True  currentSource False
  M2-AC13  level A  referencesValid True  currentSource False
```

`referencesValid` stayed true because neither record cites a file #111 touched; only the
currency rule tripped. Rendered as the four counts this slice adds, the same tree reads:

| Count | Value at `c3bbc5c` |
|---|---:|
| (a) checkbox checked in a milestone `ACCEPTANCE.md` | **13** |
| (b) a passing record whose cited bytes still match | **2** |
| (c) a passing record whose source still describes HEAD | **0** |
| (d) a passing record at the prescribed A/C/I/H/R level | **2** |
| of which: checked with **no record at all** | **11** |
| **qualified** — one single record answering all four | **0** |

That is the conflation stated as numbers. A reader who trusts the checkboxes sees 13; the
truthful figure is 0; and eleven of the thirteen are not stale records but rows the ledger
says nothing whatever about, which is why `claimed-without-record` is its own verdict and
`checkedWithNoRecord` its own count rather than being folded in with `stale-source`. Note
that (d) reads 2 rather than 0: "a passing record exists at the prescribed level" and "the
prescribed level is actually satisfied" are different questions, and only the `qualified`
row answers the second. Keeping them apart is the point.

`scripts/evidence_currency.py` would have fired on exactly this merge, reporting `main`
carries two records whose `currentSource` is false. It is not a hypothetical check.

### This slice has the same property, and that is not a defect

`scripts/` is not exempt either, so adding `scripts/evidence_currency.py` and
`scripts/manifest_audit.py` and editing `scripts/traceability_report.py` stales M2-AC04
and M2-AC13 the moment this merges. The diagnostic already shows both as `stale-source`
on this branch. The #106 and #109 commit messages each observed that a re-seal check in CI
"would be worth adding" and each deliberately deferred it, for precisely this reason: the
check is itself a `scripts/` change needing its own re-seal afterwards. Adding it does not
escape that, it accepts it once. The instances now stand as #105 into #106, #109 into
`d6f03d7`, #111 into the dip measured above, and this slice into the re-seal that must
follow it. Stated here so the next agent meets it as a documented property rather than a
surprise.

It is also the concrete reason `--gate-stale` stays off in CI: enabling it in this same
commit would turn `main` red on merge for a dip this commit itself creates, and the
cheapest route back to green would be deleting the two records.

## Manifest policy investigation and recommendation (issue #87)

Full evidence and history table: [ADR 0004](../adr/0004-manifest-integrity-scope.md).
Measured at `d6f03d7` with `python3 scripts/manifest_audit.py`: 493 tracked files, 347
entries, **145 omitted** (up from the 118 in the issue body and the 123 in its comment),
0 stale digests, 0 absent paths, 0 untracked entries. The omissions are 76 Swift sources
(39 LabelCore, 37 LabelMac), 60 `docs/validation/*` receipts and 9 scripts, tests and
documents — including `scripts/traceability_report.py`, `docs/TRACEABILITY.md` and
`docs/ACCEPTANCE-EVIDENCE.json`, the evidence system's own inputs.

**Recommendation: option 1, whole-tree integrity control, staged — and the backfill is
the maintainer's to make.** Walking the manifest's whole history settles the scope
question the issue framed as open. Coverage began at exact whole-tree parity — 280
entries over 281 tracked at the first commit that carried the file — and stayed within
one entry for twenty commits, until `56fdc7b` added 116 tracked files (55 Markdown, 52
Swift, 6 Python, 3 JSON) without a single entry and took the gap from 1 to 117 in one
step. The "mixed convention" is therefore not two conventions but one that stopped being
applied at a known commit; option 2 would mean writing down a scope matching neither the
file's history nor its 347 current entries, since the 92-file archive statement in
`docs/HANDOFF-VALIDATION.md` describes the revision-2 handoff archive, a different
artifact predating this repository. Option 3 is premature: the ledger binds 20 distinct
files today, not 347, and `source_is_unchanged` reads the manifest directly, so retiring
it is a change to the currency rule and a two-order-of-magnitude reduction in integrity
coverage.

One correction to the issue's own reasoning, because it changes what option 1 buys. The
comment argues a truthful manifest "now genuinely gates acceptance currency — but only
over the paths it covers". Reading `source_is_unchanged`, currency is decided by the
diff, not the manifest: any changed path outside evidence metadata, `docs/validation/*.md`
and the milestone `ACCEPTANCE.md` files already denies currency, so a change to an
*uncovered* Swift source invalidates every record exactly as a covered one does. The
manifest's real role is a ratchet that stops a **manifest-only** commit claiming the
exemption unless the refresh is truthful and does not shrink coverage. Option 1 should be
argued on integrity grounds; it adds no currency enforcement.

Implemented here: **measurement only**, plus the audit's two enforcement flags, both off.
`--enforce-covered` (stale digest, absent path, untracked entry) is already satisfiable
with zero backfill since all three counts are zero, and is left off solely because four
workstreams are in flight and enabling it mid-flight would fail branches over a file none
of them own. `--enforce-coverage` belongs with the 145-entry backfill, which is the
maintainer call the issue reserves. The one manifest edit in this slice covers its own
ten touched files — a widening refresh, which `manifest_describes_tree` explicitly
permits and which therefore invalidates no record.

## Artifacts

No binary artifact is retained. The new tests create synthetic git repositories under
`tempfile.TemporaryDirectory` and delete them; two of them assert byte-for-byte that
neither tool modifies the repository it inspects. No hosted CI run exists for this branch
yet; the controller opens the pull request.

## Not run, and why

- `swift test --package-path Packages/LabelMac` — **NOT RUN**. `Package.swift` declares
  `platforms: [.macOS("26.0")]` and the target imports CryptoKit, Darwin and
  CoreGraphics. It cannot build on this Linux host. No file in `Packages/` is touched by
  this slice, so nothing here depends on it.
- `bash scripts/ci-swift.sh` — **NOT RUN**. It requires macOS and `xcrun`.
- Hosted GitHub Actions — **NOT RUN**. The workflow change is validated only by PyYAML
  parsing and by reading the diff; no Actions run has executed these two steps. Their
  first real execution is the pull request this branch feeds.
- `codesign`, Gatekeeper, quarantined download, privileged or helper installation, CUPS
  queue or filter execution, system print dialog, browser workflow, USB transfer,
  physical label, barcode scan, cutter or peeler operation, update, uninstall,
  notarization — **NOT RUN**, none attempted, none implied.

## Limitations / next action

Linux, Swift 6.1.3, CPython 3.11, evidence level A, and the subject is bookkeeping rather
than product behaviour. This slice qualifies no macOS, GUI, installed-scheduler, hardware
or release row, and the diagnostics cannot: they read a ledger of maintainer declarations
and check digests, ancestry and levels. `readyForMaintainerReview` remains false, 0 of 21
requirements are satisfied, and the report reads 2 criteria with records and 88 without.
Hardware, release and GUI rows stay NOT RUN; neither a green `repository-preflight`, a
hosted compile, nor the inert `labelprobe` sink promotes any of them, and the new
`LEVEL-PROMOTION` finding exists to make an attempt to do so a build failure.

Known gaps this slice does not close:

- The eleven `claimed-without-record` boxes and the one I-level row among them are
  reported, not corrected. Correcting them edits milestone `ACCEPTANCE.md` files or the
  ledger, which this slice deliberately does not touch.
- `--gate-stale` is not enabled, so a stale record on `main` is visible in the CI log but
  does not fail the build. Enabling it is a one-line workflow change once the maintainer
  accepts a red `main` between a source PR and its evidence PR — `c3bbc5c` is what such a
  red `main` would have looked like.
- The `c3bbc5c` figures were measured by the controller in a separate worktree, not in
  this one; this branch is based on `d6f03d7` and is not rebased. They are reproduced here
  as reported, and the same numbers are reproduced independently by this branch's own run
  at `d6f03d7`, where the counts are identical because #111 changed no acceptance input.
- The 145-entry manifest backfill and `--enforce-coverage` are not done.
- The two workflow steps have never executed on a runner.

Next action: an evidence slice against the merged result re-sealing M2-AC04 and M2-AC13,
then the maintainer's decision on ADR 0004.

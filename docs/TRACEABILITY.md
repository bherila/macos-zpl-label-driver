# Acceptance evidence and traceability

Run `python3 scripts/traceability_report.py` for a read-only JSON report of all
acceptance IDs and mandatory/optional requirement mappings. Repository preflight
validates the ledger schema and references; the native CI sequence also runs the
actual source-bound CLI. Neither command submits jobs or qualifies hardware.

[ACCEPTANCE-EVIDENCE.json](ACCEPTANCE-EVIDENCE.json) holds explicit maintainer
assessments. It starts empty: milestone-wide prose and checked boxes alone are not
per-acceptance evidence. Existing narrative evidence remains available for deliberate
review/backfill; do not automatically promote it to a pass declaration.

Each record has exactly these fields:

```json
{
  "acceptanceID": "M3-AC01",
  "level": "A",
  "state": "not-run",
  "sourceSHA": "0000000000000000000000000000000000000000",
  "implementation": [],
  "evidence": []
}
```

The example is a shape illustration, not a valid pass or an observed source revision.
Reference lists contain objects with exactly `path` (repository-relative) and
`sha256` (the exact file-byte digest). Use real evaluated source commits and evidence
files; no customer labels, credentials, private addresses, printer serials or full logs.
A/C/I/H/R are orthogonal evidence levels, not interchangeable ranks. Supported states
are not-run/pass/fail/blocked/not-applicable. Not-applicable is not a global pass.

A current declared pass requires the exact prescribed level, nonempty valid implementation
and evidence references, a complete acceptance checkbox, and a clean workspace. Failed or
blocked current assessments at any level veto readiness for that acceptance item. Empty,
stale, corrupt, unknown, duplicate or over-budget records cannot count as pass.

Evidence commits may follow the evaluated source commit. The CLI permits ancestor source
commits only when differences are restricted to the explicit evidence metadata files,
validation Markdown and acceptance checklists. Build inputs and requirement/criterion
metadata must remain unchanged. It never infers candidate equivalence across code changes,
rebases or unrelated histories. Reference hashes are still checked against the current
files, and HEAD/dirty state are read again before publishing the report to stdout.

All file reads use descriptor-relative no-follow traversal and reject non-regular or
hardlinked files before reading. Limits: 2 MiB per file, 64 MiB distinct reference bytes,
512 assessments/source revisions, 16 references per list, 16 milestones / 256 criteria each,
and a cooperative 60-second report budget with finite 10-second Git calls. References are
cached only while their descriptor fingerprints remain unchanged. No external diff or
text conversion is executed. Malformed input produces no qualification result.

`readyForMaintainerReview` means the mandatory mappings have complete current declared
assessments and valid references. It is not independent verification of their semantics,
a hardware receipt, a release qualification, or permission to merge/publish. Actual
runtime, installation, printer and release evidence and human disclosure/correctness
review remain required. No physical row is qualified by this tooling.

## Four separate questions about one row

A row that reads "complete" has historically conflated four independent things. The report answers
each separately in `evidenceStatus`, because a row can answer some and not others:

| Field | Question | Source of truth |
|---|---|---|
| `checkboxComplete` | Is the box checked? | the milestone `ACCEPTANCE.md` |
| `hasDigestValidRecord` | Does a passing record's cited bytes still hash to what it recorded? | `ACCEPTANCE-EVIDENCE.json` against the working tree |
| `hasCurrentSourceRecord` | Does a passing record's evaluated source still describe HEAD? | `source_is_unchanged` |
| `hasRequiredLevelRecord` | Is a passing record at the level [VALIDATION-PLAN.md](VALIDATION-PLAN.md) prescribes? | `milestones.json` |

These four booleans diagnose; they do not qualify. Each may be answered by a different record, so
`qualified` additionally requires one single record to answer all four at once — that is exactly
`meetsRequiredDeclaredEvidence` on that record, plus a checked box and no current blocker.
`promotesBelowRequiredLevel` is set when a row prescribing I, H or R carries a passing A or C
record; no offline suite, hosted compile or inert check ever promotes such a row.

`evidenceCounts` reports the four as four separate figures over every row, plus
`checkedWithNoRecord` — a checked box the ledger says nothing at all about, which is a different
state from a stale record and is counted on its own. Measured on `main` at `c3bbc5c` immediately
after #111 merged: **13** checked, **2** digest-valid, **0** current, **2** at the prescribed
level, **11** checked with no record at all, **0** qualified. A reader who trusts the checkboxes
sees 13; the honest number is 0. Collapsing those into one figure is the failure this table exists
to prevent.

`verdict` names the first unanswered question of the record that answers the most of them, drawn
from a fixed vocabulary: `qualified`, `stale-source`, `invalid-references`, `wrong-evidence-level`,
`claimed-without-record`, `record-without-checkbox`, `no-passing-record`, `current-blocker`,
`no-record`. `evidenceSummary` counts every row exactly once by verdict. A row that is checked and
digest-valid but stale reads `stale-source`, never `qualified`.

## Read-only currency diagnostic

`python3 scripts/evidence_currency.py` turns the above into an exit code for CI. It is read-only:
it never refreshes a digest, re-seals a record, edits a checkbox or promotes a claim, and every
finding names a file a human has to change.

- exit 0 — evaluated, no gating finding
- exit 1 — evaluated, at least one gating finding
- exit 2 — could not evaluate

There is no fourth outcome. An absent, empty or malformed `MANIFEST.sha256`, an unreadable or
too-deeply-nested ledger, a record that is not an object, a missing git history, a recorded
`sourceSHA` this repository does not hold, a failed Git call, an exhausted report deadline or a
workspace that changes mid-run is exit 2, never a quiet pass. A recorded commit that is absent —
a shallow clone, rewritten history, a SHA that was never pushed — is deliberately *not* folded
into staleness: `merge-base --is-ancestor` fails identically for an absent object and for an
honest non-ancestor, so the commit is confirmed to exist before its currency is judged or cached.
An existing commit that simply is not an ancestor remains ordinary `STALE-SOURCE`.

Gating findings are the ones that are wrong regardless of sequencing: `MISSING-BINDING` (a record
with an empty `implementation` or `evidence` list), `INVALID-REFERENCES`, `WRONG-EVIDENCE-LEVEL`,
`LEVEL-PROMOTION` and `CURRENT-BLOCKER`. Each is read from the row's passing **records**, not from
its `verdict`. `verdict` names one cause per row by design, so a row holding a stale-but-valid
record beside a current one citing a wrong digest summarises as `stale-source`; that lossiness is
right for a summary and wrong for a gate. The same rule that stops the four dimension booleans
combining to qualify a row stops the single verdict hiding a gating defect underneath a
non-gating one — or underneath a `qualified` sibling record. A re-seal rewrites a record in place
rather than appending, so every passing record in the ledger is live and a wrong digest on any of
them gates. `CLAIMED-WITHOUT-RECORD`, `NO-PASSING-RECORD`, `RECORD-WITHOUT-CHECKBOX` and
`WORKSPACE-DIRTY` are reported, since fixing them means editing acceptance claims a human owns.

### `STALE-SOURCE` is reported on every event, including pushes to `main`

Stated plainly, because it is the one finding whose severity is a choice: **CI passes
`--gate-stale` on neither `pull_request` nor `push`.** A stale record on `main` is printed in the
`repository-preflight` log and does not fail the build. Nothing exercises the flag except this
repository's own tests.

The reason is sequencing, not convenience. A source slice *necessarily* stales every record —
the repository's own rule is that a record written in the same commit as its source cannot bind
that commit — so gating staleness on pull requests would fail the very PR doing the work, and the
cheapest route back to green would be deleting records. AGENTS.md forbids silently lowering
acceptance criteria to obtain a green build, and a gate whose easiest fix is deleting evidence is
that pressure by construction.

Gating only the `push` event escapes that objection and is the obvious next step, but it buys the
closure at a stated price: `main` goes red between a source merge and its re-seal slice, **every
time**, on a required check. That is a maintainer's call about the branch, not a tool default,
and it is recorded as open in
[the slice evidence](validation/M6-EVIDENCE-CURRENCY-2026-09-19.md). Until it is made, the
honest statement is the one above: staleness on `main` is visible, not enforced.

`python3 scripts/manifest_audit.py` measures what `MANIFEST.sha256` actually covers. It writes
nothing; the scope decision is recorded in [ADR 0004](adr/0004-manifest-integrity-scope.md). A
manifest is untrusted input on a fork's pull request, so an entry is a path *claim*, not a path to
open: a name that is absolute, carries `..` or `.` components, or holds a backslash or NUL is
refused while parsing, before any `is_file`, `stat` or read. Every component of an accepted name
is then opened `O_NOFOLLOW` relative to the previous descriptor, so a symlinked directory inside
the tree cannot redirect a read outside it either, and at most 2 MiB + 1 byte is read from any
file — the extra byte is what proves the cap, which is enforced while reading rather than checked
against `st_size` afterwards.

### `INVALID-REFERENCES` gates a source slice that touches a cited path

The gating list above has a consequence worth stating on its own, because it is the one that
costs a contributor a build rather than a re-read. `INVALID-REFERENCES` is severity `GATE`
unconditionally: unlike `STALE-SOURCE` it does not wait for `--gate-stale`, so it fails every
pull request, not only a `main` push. A slice that changes one byte of a file a live record
**cites** therefore cannot merge, and that includes a slice which only adds a test to that file.

PR #148 is the worked example. It added assertions for `M3-AC04` inside
`Packages/LabelMac/Tests/LabelMacTests/ProfileBoundFinishingJobPlanTests.swift`, which `M3-AC03`
cites as evidence. The assertions were correct and the manifest was refreshed correctly; the
digest the ledger holds for that file simply stopped matching, and preflight refused the change.
Clearing it by re-hashing is forbidden — *if a cited file changed, that is a new claim and needs
its evidence re-run, not a quiet re-hash* — and re-running `M3-AC03` means a hosted macOS pass,
which is a different slice from the one in front of you. #149 landed the same substance in a new
file with `ProfileBoundFinishingJobPlanTests.swift` untouched, and passed.

So there are exactly two honest routes, and they are chosen **before** writing, by reading the
cited paths out of `docs/ACCEPTANCE-EVIDENCE.json`:

1. put the new coverage in a new file, leaving every cited byte alone; or
2. re-run the cited record's evidence and rebind it in the same slice — which for anything under
   `Packages/LabelMac` needs a macOS host, since Linux cannot build that package.

Neither is a workaround. The gate is doing its job: a record binds bytes, and bytes that moved
are no longer the bytes it attested to. What the gate cannot tell you is which of the two routes
your change wants, and that is a judgement made cheaply at the start and expensively after CI.

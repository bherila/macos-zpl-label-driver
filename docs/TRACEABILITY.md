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

There is no fourth outcome. An absent, empty or malformed `MANIFEST.sha256`, an unreadable ledger,
a record that is not an object, a missing git history, an exhausted report deadline or a workspace
that changes mid-run is exit 2, never a quiet pass.

Gating findings are the ones that are wrong regardless of sequencing: `MISSING-BINDING` (a record
with an empty `implementation` or `evidence` list), `INVALID-REFERENCES`, `WRONG-EVIDENCE-LEVEL`,
`LEVEL-PROMOTION` and `CURRENT-BLOCKER`. `STALE-SOURCE` is reported rather than gating by default,
because a source slice necessarily makes every record stale until its evidence slice lands and
gating it would fail the PR doing the work; `--gate-stale` turns it into a failure for a
main-push gate. `CLAIMED-WITHOUT-RECORD`, `NO-PASSING-RECORD`, `RECORD-WITHOUT-CHECKBOX` and
`WORKSPACE-DIRTY` are reported, since fixing them means editing acceptance claims a human owns.

`python3 scripts/manifest_audit.py` measures what `MANIFEST.sha256` actually covers. It writes
nothing; the scope decision is recorded in [ADR 0004](adr/0004-manifest-integrity-scope.md).

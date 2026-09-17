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

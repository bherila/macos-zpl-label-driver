# Manifest coverage taken to whole-tree, and enforced — 2026-09-19

Level C (repository/configuration). Closes the scope question in issue #87 by taking ADR 0004's
recommended option 1, in the staging that ADR prescribes. No acceptance ID advances and no evidence
level is claimed for any macOS, GUI, scheduler, hardware or release row.

## What was decided

ADR 0004 recommended **option 1, whole-tree integrity control**, and left the decision to the
maintainer. It is now taken. The ADR's own evidence is why option 1 rather than the alternatives:

- Option 2 (archive-scoped) is contradicted by the file's history. Coverage began at exact whole-tree
  parity — 280 entries over 281 tracked files at `55a9ef5` — and held within one entry for twenty
  commits. `56fdc7b` then added 116 tracked files with zero manifest entries, taking the gap from 1
  to 117 in a single step, and nothing resumed it. The 92-file archive statement in
  `HANDOFF-VALIDATION.md` describes the revision-2 handoff archive, a different artifact predating
  this repository.
- Option 3 (retire) is incoherent while `source_is_unchanged` reads the manifest directly and the
  ledger binds 29 files rather than 520.

## The two steps

**Step 2 — `--enforce-covered`.** Gates only on entries the manifest already claims: a drifted
digest, a path that no longer exists, an entry naming an untracked file. All three read zero on
`main`, so turning it on changed no build outcome. The ADR deferred it "only because four workstreams
are in flight"; all four have merged, so that condition expired.

**Step 3 — backfill, then `--enforce-coverage`.** 164 entries added in one reviewable commit, taking
coverage from 356 of 521 to **520 of 521**. The single uncovered path is `MANIFEST.sha256` itself,
which never describes itself. This is a widening refresh, which `manifest_describes_tree` explicitly
permits, so it invalidates no acceptance record.

## The cost, and why the helper is not optional

Option 1's real cost is a manifest refresh on every pull request that touches a covered file — and at
whole-tree coverage that is nearly every pull request, including every `docs/validation` receipt.

That cost was demonstrated immediately: enabling step 2 edited `.github/workflows/ci.yml`, which is
covered, and the new gate failed **that very commit** on its own stale digest. A tax paid by hand is
a tax eventually forgotten, and forgetting is how the gap reached 164 in the first place.

`scripts/refresh_manifest.py` pays it in one command. It imports every path rule, size cap and
symlink defence from `manifest_audit` rather than restating them, so the reading and writing halves
cannot drift — an entry is hashed exactly as the audit hashes it, through one `O_NOFOLLOW` descriptor
chain, refusing anything over the 2 MiB cap. Two refusals are deliberate:

- **An entry is never removed.** `manifest_describes_tree` permits widening and forbids shrinking,
  because a dropped entry is corrupted integrity metadata rather than bookkeeping. Removing a path
  stays a manual edit a reviewer must see.
- **An absent, unreadable or oversized file keeps its recorded digest** and is reported. Rewriting it
  to a placeholder would turn an integrity failure into a clean build — the exact inversion this
  manifest exists to prevent.

`refresh_manifest.py` is in `check_repo`'s REQUIRED list so the one command that pays the tax cannot
vanish, and `CONTRIBUTING.md` says how to use it.

## Coverage proven by mutation, not asserted

Both gates were shown to bite and then restored:

| Mutation | Gate | Result |
|---|---|---|
| One covered `.swift` digest set to 64 zeros | `--enforce-covered` | `STALE-DIGEST`, exit 1 |
| A new tracked file with no manifest entry | `--enforce-coverage` | `UNCOVERED-PATHS`, exit 1 |
| Both restored | both | exit 0 |

Seven new tests cover the helper: a drifted digest refreshed in place, the never-remove rule,
backfill widening without ever covering the manifest itself, an absent file keeping its recorded
digest rather than a placeholder, byte-sorted output stable across runs, the entry cap, and that
`refresh()` itself writes nothing.

## Validation

Linux x86_64, Swift 6.1.3, CPython 3.11. All exit 0:

| Command | Result |
|---|---|
| `python3 scripts/check_repo.py` | preflight passed |
| `python3 -m unittest discover -s scripts/tests` | **168 tests, OK (skipped=2)** — up from 161 |
| `swift test --package-path Packages/LabelCore` | 329 tests, 0 failures |
| `python3 scripts/traceability_report.py` | exit 0 |
| `python3 scripts/evidence_currency.py` | exit 0 |
| `python3 scripts/manifest_audit.py --enforce-covered --enforce-coverage` | exit 0 |
| `sha256sum -c MANIFEST.sha256` | **520 of 520 OK** |
| `python3 scripts/run-accelerator-checks.py` | PASS |
| `git diff --check` | clean |

`.github/workflows/ci.yml` parses under PyYAML with all three jobs intact.

**NOT RUN:** `swift test --package-path Packages/LabelMac` and `bash scripts/ci-swift.sh` are
macOS-only; no Swift file is touched by this slice. The changed workflow step is evaluated only by
GitHub Actions, so the hosted run on this pull request is its first execution of both flags together.

## Scope and what is owed

One correction carried forward from ADR 0004, because it bears on how much this buys: coverage is an
**integrity** control, not a currency control. `source_is_unchanged` decides currency from the diff,
so a change to a previously uncovered Swift source already invalidated every record exactly as a
covered one did. What whole-tree coverage adds is that one command now answers "has any tracked byte
changed without being recorded". It does not tighten acceptance enforcement.

This slice changes `.github/` and `scripts/`, neither exempt, so it stales `M2-AC04` and `M2-AC13`
again — the eleventh and twelfth instances of the sequencing rule. A re-seal against the merged
result is owed. PR #123 remains open and held, and merging it later will owe another.

Hardware, GUI, installed scheduler, administrator, USB, printer and every release row remain NOT RUN
and are untouched.

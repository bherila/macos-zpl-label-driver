# ADR 0004 — What `MANIFEST.sha256` is for

Status: proposed — the scope decision is the maintainer's and is not taken here
Date: 2026-09-19
Decision owner: maintainer (issue [#87](https://github.com/bherila/macos-zpl-label-driver/issues/87))
Related requirements / acceptance IDs: none claimed. This ADR records a measurement and a
recommendation; it advances no acceptance row.

## Context and observed evidence

Environment: Linux x86_64, Python 3.11, git. Measured on `codex/m6-evidence-currency` against
`main` at `d6f03d75e48baef4a9afb10333f2d73987cf93ff`, reproducible with
`python3 scripts/manifest_audit.py`.

| Measure | Value at `d6f03d7` |
|---|---:|
| tracked files | 493 |
| manifest entries | 347 |
| covered tracked files | 347 |
| omitted tracked files (excluding the manifest itself) | 145 |
| stale digests among covered files | 0 |
| entries naming an absent path | 0 |
| entries naming an untracked path | 0 |

Issue #87 measured 118 omitted at `56fdc7b` and its comment measured 123 at PR #85's head. The
figure is now 145: the gap is still growing, and every measurement since has been taken after the
fact rather than by a check.

The omissions are not scattered. 76 are Swift sources (39 LabelCore, 37 LabelMac), 60 are
`docs/validation/*` receipts, and the remaining 9 are scripts, tests and documents — including
`scripts/traceability_report.py`, `docs/TRACEABILITY.md` and `docs/ACCEPTANCE-EVIDENCE.json`, which
are the evidence system's own inputs.

**The decisive finding is that this manifest has never been archive-scoped in this repository.**
Walking its whole history, coverage began at exact whole-tree parity and stayed there:

| Commit | Date | tracked | entries | uncovered |
|---|---|---:|---:|---:|
| `55a9ef5` (first manifest commit) | 2026-09-17 | 281 | 280 | 0 |
| `9355051` | 2026-09-17 | 312 | 311 | 0 |
| `565af60` | 2026-09-17 | 327 | 325 | 1 |
| `5605999` (#79) | 2026-09-18 | 349 | 347 | 1 |
| `56fdc7b` | 2026-09-18 | 465 | 347 | **117** |
| `9527188` (#109) | 2026-09-18 | 492 | 347 | 144 |

One commit accounts for the break. `56fdc7b` changed 160 files and added 116 tracked files — 55
Markdown, 52 Swift, 6 Python, 3 JSON — without adding one manifest entry, taking the gap from 1 to
117 in a single step. Before it, the single uncovered path was
`docs/validation/M0-SWIFT-CACHE-2026-09-17.md`. Everything since has simply accumulated on top.

So the "mixed convention" the issue describes is not two competing conventions. It is one
convention — whole-tree coverage, maintained deliberately across 20-odd commits — that stopped
being applied at a known commit and was never resumed. The archive-scoped reading rests on
`docs/HANDOFF-VALIDATION.md`, which says the **revision-2 handoff archive** contained 92 files and
that its manifest covered every packaged file except itself. That is a true statement about a
different artifact that predates this repository's first commit. The file in this repository was
whole-tree from its first appearance, at 280 entries, three times the archive's size.

A second correction matters for how much option 1 is worth. The issue comment argues that because
#85 made the evidence exemption conditional on the manifest still describing the tree, "a truthful
manifest now genuinely gates acceptance currency — but only over the paths it covers". Reading
`source_is_unchanged` closely, that overstates what the manifest does. Currency is decided by the
diff: any changed path that is not evidence metadata, `docs/validation/*.md`, a milestone
`ACCEPTANCE.md` or the manifest itself already returns `False`, whatever the manifest says. A
change to an uncovered Swift source therefore still invalidates every record, exactly as a covered
one does. The manifest's actual role is narrower and worth stating precisely: it is a ratchet that
keeps a **manifest-only** commit from claiming the exemption unless the refresh is truthful and does
not shrink coverage. Coverage buys integrity metadata over more of the tree; it does not buy extra
currency enforcement. Option 1 should be argued on integrity grounds, not on currency grounds.

## Options considered

**1. Whole-tree integrity control.** Add the 145 missing entries and enforce digests so drift fails
CI. Restores the repository's own original convention and makes one command answer "has any tracked
byte changed without being recorded". Cost: every PR touching a covered file must refresh the
manifest in the same commit, which is a real workflow tax on every contributor and every parallel
branch. It also interacts with the evidence sequencing rule — a manifest refresh is exempt, so it
does not add a re-seal, but a contributor who forgets it now gets a red build instead of silence.

**2. Keep it archive-scoped.** Document that it covers packaged artifacts only. This option is not
available on the evidence above: the file has never been archive-scoped here, 347 entries do not
describe a 92-file archive, and there is no rule that would explain why 84 of 144 validation
receipts and 125 of 201 Swift sources are inside it. Adopting this would mean writing down a scope
that matches neither the file's history nor its contents.

**3. Retire it.** The evidence ledger binds by digest the files that matter. But the ledger binds 20
distinct files today across two records, not 347, and `source_is_unchanged` reads the manifest
directly, so retiring it is a code change to the currency rule and a reduction in integrity
coverage of two orders of magnitude. Retirement is only coherent after deciding the ledger is the
sole integrity control, which is a larger decision than this one.

## Decision

Not taken here. Bulk-adding 145 entries and turning on enforcement changes what every future PR must
do, and issue #87 is explicit that this is a maintainer call. **The recommendation is option 1**,
because it restores a convention this repository actually had rather than inventing one, and because
options 2 and 3 are each contradicted by a measured fact above. The recommendation is qualified:
option 1's value is integrity coverage over the tree, not stronger acceptance-currency enforcement,
and its cost is a manifest refresh on every PR that touches a covered file.

Suggested staging, each step independently reversible:

1. Measure on every CI run. **Done in this slice** — `scripts/manifest_audit.py` runs in
   `repository-preflight` and prints coverage, drift and the per-area breakdown. It exits 2 when it
   cannot measure and 0 otherwise, so today it changes no build outcome.
2. Enforce over the existing scope: `--enforce-covered` fails on a stale digest, an absent path or
   an untracked entry. All three are zero today, so this can be turned on without any backfill. It
   is left off here only because four workstreams are in flight and enabling it mid-flight would
   fail their branches for a file none of them own.
3. Backfill the 145 omissions in one reviewable commit, then enable `--enforce-coverage`. This is
   the maintainer decision. It is a widening refresh, which `manifest_describes_tree` explicitly
   permits, so it does not invalidate any acceptance record.

Nothing in step 3 is implemented here. The only manifest edit in this slice is the addition of this
slice's own new files, which is a widening refresh consistent with the convention above and with the
per-PR practice that held until `56fdc7b`.

## Validation and migration

`scripts/manifest_audit.py` is read-only and tested by `scripts/tests/test_manifest_audit.py`
(13 cases): partial and full coverage measurement, a drifted digest, an entry whose path is gone, an
entry for an untracked path, a symlinked entry that is never hashed through, five malformed manifest
bodies, a repeated path, a non-UTF-8 manifest, an absent manifest, a directory without git, a
byte-for-byte proof that the audit writes nothing, and the three CLI exit codes. Every unreadable or
malformed input is exit 2, never a quiet 0.

Reversibility: steps 1 and 2 are flags on one script. Step 3 is a single commit that can be
reverted; because widening is permitted and shrinking is not, a revert after further work would be
caught by `manifest_describes_tree` rather than silently accepted.

Reconsider this ADR if the ledger grows to bind most of the tree by digest, which would make option
3 coherent, or if a contributor workflow measurement shows the per-PR refresh cost of option 1
exceeds the integrity it buys.

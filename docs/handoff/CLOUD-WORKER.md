# Cloud worker handoff — 2026-09-17

Repository: bherila/macos-zpl-label-driver.

## Published checkpoints
- codex/cloud-implementation-handoff: full latest implementation based on local source a347ee19450700f73cd04743595bc8480eda7950, plus this handoff. It contains every independent implementation commit previously unavailable on GitHub.
- codex/stack82-prefix38-handoff: prepared linear PR2–38 ancestry, plus docs/handoff/STACK82-PREPARED-2-38.json. The map names original remote heads, old base bounds and prepared heads/bases. All prepared objects are ancestors of this checkpoint; restore local branches from those SHAs after fetching this checkpoint. These are checkpoint branches, not PR replacements.

## Priority and authorization
Maintainer authorized squash merge#1, then prioritize squash merging through#38, then resume implementation. #1 is MERGED; verified main072dbe3badee66c324359422d610e4f226010277. Native stack82 contains58PR2–59. No other PR merged. No releases authorized. Do not merge39+ under the minimum-prefix authorization without clarification.

Existing PR2 published head db1cb431bd94c17bbc83af45c8421de4a2d11a95 includes finite page-box corner fix and regression; hosted run35284656496 preflight passed/macOS queued at last readback. Refresh live; maintainer permits handoff before CI finishes. Do not treat queued as passed.

Prepared PR2–38 are LOCAL-ONLY on the checkpoint, not published as existing PR heads.37layers passed parent-ancestry and zero-merge-commit checks. Each layer's source delta from original is limited to separately merged#1 and the geometry fix/test. Full prepared38 native sequence passed166Core/152Mac debug AND release,64Python, both accelerator modes, ARM/min26 metadata, ad-hoc signatures and packaged-worker equality. Actual host27.0, not retail-runtime26 qualification. Normalizing freshly rebased committer metadata preserved every tree exactly; map records testedPreparedHead as well as preparedHead. No device/queue/privilege operations.

Official gh-stack rebase initially failed determining PR3 old base and restored every branch; manual rebase used explicit captured oldBase bounds. Manifest conflicts regenerated from files; PROGRESS only independent evidence additions merged; inspected HANDOFF append conflicts retained both histories and removed one exact duplicate. No source conflict resolved manually. Higher PR39–59 remain at original heads and still need restacking.

IMPORTANT: AGENTS.md prohibits force-pushing shared branches. gh stack push explicitly uses per-branch --force-with-lease and is non-atomic. Existing merge authorization has NOT been treated as an exception to this prohibition. Obtain a specific maintainer exception before rewriting existing PR heads. Compare every current remote head to recorded oldHead before any approved rewrite; refuse mismatches and protect peers. Do not change main directly. Fresh exact-head hosted checks are required after the rewrite. No unresolved review threads on2–38 at last fresh GraphQL audit; recheck. No Codex review requests posted in this sequence.

## Implementation after merge priority
Read AGENTS.md and mandatory docs in implementation checkpoint. Latest implemented margins span finite portable placement, immutable workflow-v3 JSON/drafts/imports/planned labels, original-PDF visible-area clipping, strict private conversion-ticket-v3 and actual subprocess propagation, native margin controls and atomic review/generation/cancellation. Legacy-v2 zero bytes/request shape preserved. Latest portable checkpoint admits workflow3 references in resolved tickets/finishing queues, rejects stale planned margins and mismatched snapshots;311Core debug/release and accelerator debug passed. Native accepted-store snapshot/revision proof and contract reconciliation for this last change remain PENDING. Do not retain stale CONTRACTS statement that queue-v3 admission is disabled without reconciling current code. No current whole-source acceptance/hosted proof claimed.

Previous full implementation baseline77de47c passed305Core/380Mac both/signatures; later additions have scoped receipts, not a refreshed full baseline. Editor margin slice23native both plus app packaging passed; private worker margin slice53native both passed. Canonical docs/HANDOFF.md and docs/PROGRESS.json contain receipts. Do not flatten/squash all unpublished source into old PR38. Reconcile overlapping early geometry fix/shared later validator when integrating after merges.

## Cloud validation and manual gates
Linux: run python3 scripts/check_repo.py; python3 -m unittest discover -s scripts/tests; swift test --package-path Packages/LabelCore; same -c release; accelerator debug/release according to current scripts. Use finite timeouts and each command's own exit. Record NOT RUN for LabelMac/native signatures/CoreGraphics/GUI on Linux. CI standard GitHub-hosted runners only; no private-printer reachability or untrusted self-hosted runs.

Issue80PartA passed earlier repaired GUI, not current GUI/VO qualification. PartB frozen source52ba93f is on maintainer Mac only; no result claimed, no cloud recreation using consent. Production adapter remains unselected; installer/helper integration awaits actual scheduler/no-account authorization/rollback proof. No printer I/O authorized. GC420d USB4×6precut tear-off/no cutter, native8dots/mm; unit identity/sensing/settings/status unknown. No privileged installs, labels/commands, calibration/reset/firmware or releases. Do not equate software tests with installed or physically printed.

Local session stopped for computer sleep; persistent goal remains unfinished. Cloud worker may resume using this handoff. All implementation/prepared source is in the two checkpoints; local build products/private frozen manual candidate are intentionally not uploaded.

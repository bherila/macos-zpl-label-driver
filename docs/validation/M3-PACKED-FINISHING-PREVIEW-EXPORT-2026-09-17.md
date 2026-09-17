# Packed accepted finishing preview export — 2026-09-17

Partial application integration advancing the exact-preview software contract. Export accepts
only PreparedAcceptedFinishingJob from the verified store factory. Each PBM is the actual
ordered raster's pbmData, without rerendering or resampling. A bounded manifest binds accepted
record/source hashes and ordered raster hashes/dimensions. Hardware completion stays unknown.
No ZPL, device command, transport, status query or delivery permission is produced.

Bounds: at most10000 labels,512MiB aggregate output including PBM headers/manifest,4MiB
manifest, finite at-most60-second deadline and cancellation checks through hashing/writes.
Publication stages0600 files in a private0700 sibling under an owned parent without group/
other write permission. Files/directory are synced; exclusive atomic rename refuses existing
output. Parent-sync/post-publication failure remains commitUncertain; final output is preserved.
Cleanup addresses only staged files and checks directory inode identity before removal.

Nearest independent constraints: exact previews cannot substitute flattering renderings;
export cannot overwrite another output or silently truncate a job to satisfy resource limits.
Thirty focused native cases passed exit0, including the prior28 and exact all-raster PBM/
manifest equality, no ZPL assets, existing-directory sentinel preservation, aggregate-budget
rejection before creation and owned-stage cleanup. CLI export integration passed31 focused native cases exit0, including actual executable
success and repeat-export refusal (exit73, empty stdout, no output path in stderr). An
additional empty-directory case passed and preserved inode/contents. Pixel/overwrite/budget
faults each failed exit1 through expected assertions; exact restored31 cases passed exit0.
Full finite900-second Mac gate session53728 passed its own exit0:104 Python/281 Core/355 native tests in debug/release, independent strict/ASCII oracles, inert ABI/pipeline checks, ARM/minimum26 metadata, local ad-hoc signatures, Developer-ID negative and packaged-worker PBM/ZPL equality. Local artifact: artifacts/setup-app.8PsoaR. Implementation checkpoint `a91cd4d77edb8ff952292c62ebb70dfdc60b475a` committed locally; nothing published.

Installed scheduler, identified unit correspondence/status, retail policy and physical printing
remain NOT RUN. Frozen Part B unchanged. No printer I/O, administrator action, merge or
publication occurred.

CLI: label-driver finishing-preview --catalog DIRECTORY --accepted-id ID --accepted-sha SHA
--preview-dir NEW_DIRECTORY [--json]. One aggregate60-second budget covers existing-catalog
inspection, original-source preparation and export. Successful output is JSON metadata, never
ZPL. Uncertain post-publication durability preserves output and reports explicit review need.

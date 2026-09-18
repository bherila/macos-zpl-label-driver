# M0 Swift build cache — 2026-09-17

Requirements: M0-AC05 and M0-AC07; no acceptance completion claimed.

Cache only LabelCore and LabelMac `.build` directories. The versioned key isolates
runner OS/architecture, deployment target, Swift version, Xcode and SDK version;
each source SHA gets a new key with a toolchain-matched fallback. All builds,
tests, independent oracles and signature checks still run after restoration.
Only successful pushes to main save caches. PRs and workflow dispatches restore
only; no signing secrets, logs or packaged distribution artifacts are cached.
Actions restore/save are pinned to the verified actions/cache v4.3.0 commit.

Repository retention was set and read back as 3 days using the GitHub cache
retention API. Storage remains at the verified 10 GB cap. No paid expansion.
Local build directories previously measured about 0.8 GB combined in an audit
checkout and 2.1 GB in an older checkout, uncompressed; hosted archive size is
unknown. After merge, a successful main push must seed the cache. Compare a
subsequent PR restore/build duration and archive size before claiming a speedup.

Validation: actionlint and repository preflight passed; all 67 Python tests
passed. Full `bash scripts/ci-swift.sh` passed exit 0 on native macOS ARM:
LabelCore 174 tests and LabelMac 223 tests in debug and release, both accelerator
configurations, independent/inert checks, local signatures and packaged-worker
equality. Workflow configuration does not change any source or acceptance gates.
Hosted cache upload/restore and timing: NOT RUN. No printer I/O or installation.

References: [cache documentation](https://github.com/actions/cache/tree/v4.3.0),
[GitHub cache API](https://docs.github.com/en/rest/actions/cache).

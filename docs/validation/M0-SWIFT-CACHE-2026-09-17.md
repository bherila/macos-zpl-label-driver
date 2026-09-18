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
checkout and 2.1 GB in an older checkout, uncompressed. The first hosted archive
is 369,189,700 bytes compressed (about 352 MiB).

Validation: actionlint and repository preflight passed; all 67 Python tests
passed. Full `bash scripts/ci-swift.sh` passed exit 0 on native macOS ARM:
LabelCore 174 tests and LabelMac 223 tests in debug and release, both accelerator
configurations, independent/inert checks, local signatures and packaged-worker
equality. Workflow configuration does not change any source or acceptance gates.
Hosted evidence observed on 2026-09-18:

- Cache PR #84 at `e3221880c7923fc22158c008d0631d16a7a918be` passed
  [run 35314770091](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35314770091),
  including actual 174/223 debug/release suites and signature/package checks.
- Squash `654fd304f7f80f0bf94296f2dd731b50d665f8c1` passed its own
  [main push 35315199048](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35315199048)
  and uploaded the first cache successfully.
- PR #61 source was unchanged between its cold `8f23b078161fd6364399248beefea5770434039b`
  and cache-integrated `0e2492b7165d7e8d135a3f169acc3466d60a9652` heads. The
  [cold native step](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35313294099)
  took 6m10s versus
  [cached native step](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35315448255)
  at 5m01s (about 19% less time). Entire macOS job: 6m20s versus 5m25s
  (about 14% less), including an 11-second restore. Actual 231-test native
  suites passed in both configurations. This is one comparison, not a guarantee.
- PR #62 also restored the main cache successfully in
  [run 35315447955](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35315447955);
  its native step took 4m00s, macOS job 4m21s. Queue time is excluded.

No CPU instrumentation, printer I/O or installation was performed.

References: [cache documentation](https://github.com/actions/cache/tree/v4.3.0),
[GitHub cache API](https://docs.github.com/en/rest/actions/cache).

# Three reference sheets through the complete inert pipeline

Date: 2026-09-16. Evidence level A, M4-AC13 PASS and partial M4-AC01 coverage.
Implementation/full-gate SHA: `4ebfd8591ad789bba06ae602d8c69c7e5049dad6`.
No installed scheduler, application-dialog, browser or physical acceptance.

The supplied original MIT fixtures and their committed source manifest are
reused without regeneration. Explicit manifest regions become three separately
named immutable workflow/virtual-queue bindings in private synthetic stores.
The existing descriptor intake, bounded native analysis/render worker, accepted
bundle, complete prepared artifact and persisted in-memory delivery are used.
Test confirmation is synthetic qualification, not a claim of user/hardware review.

| Fixture | Expected original page in PDF points | SHA-256 |
|---|---|---|
| native-vector | 288 × 432 | `24af4c33cd98b4373048c3fdf88085a1da098e7cebc97b147d051fd99ecf5c61` |
| letter-one | 612 × 792 | `e825068f01b1a5b0ca1ccfba881851506ffa4f0eec764bbaf5ecea587af24cb5` |
| a4-one | 595.2756 × 841.8898 | `f7b10360a17509bd9412042035410bcbbdf387004d12c2d0b82630069bfc8fcc` |
| layout-changed | Letter, shifted label | `63da95b75b4af7d9b397b2e6c846f0547c3b8308418e7ead21f62887a2a95f53` |

## Discriminators

The fixture writer serialized rounded A4 box coordinates; the manifest retains
pre-serialization dimensions. Explicit manifest raw rectangles are normalized
against each actual original PDF box, without inferring a crop. The resulting
selected rectangles independently retain 288 × 432 PDF points. Neither source
fixtures nor the manifest/oracle are regenerated to make results agree.

This matrix exposed avoidable numerical variation in the renderer's previous
normalized-crop-to-full-sheet expansion. After correct raw-region binding, 35
Letter/A4 text-edge dots still differed. Mapping the selected original-space
rectangle directly through the existing native transform removes that extra
expansion/division and preserves the exact equality requirement: zero differing
dots, identical complete ZPL, and the same shared native label interior. Existing
full-sheet paths and near-zero-region bounds are retained; page/region rotation
still composes before one original-document rasterization.

Original documents and distinct source digests survive acceptance. Workflow
expected input dimensions retain each original sheet, while all bind the same
`nominal-4x6` stock, 101.6 × 152.4 mm. Documented 8 dots/mm gives the independently
expected nearest-rounded 813 × 1219-dot canvas. One output reaches only the inert
sink and its complete prepared artifact is reloaded in transmitted state.

Rendering the original accepted document through its explicit plan produces an
exact PBM of the encoder bitmap; the typed encoder's complete bytes and controls
must equal the persisted worker-produced artifact. This cross-path comparison
does not replace the independent analytic encoder oracle, which stays unchanged.
Letter and A4 packed bitmaps and complete ZPL must agree exactly. Native artwork
agrees dot for dot inside a 24-dot edge inset, including frame/text/barcodes.
Only native contains deliberate sheet-corner marks within six PDF points of its
edges, so full native/Letter equality would be an incorrect oracle. Full native
bitmap inequality is required to ensure those marks were not silently discarded.

A shifted same-size `layout-changed` input and A4 submitted to the saved Letter
binding must report `layoutRejected`; an absent queue binding must report
`configurationUnavailable`. Each must leave no accepted bundle, and therefore
cannot enter prepared publication or persisted delivery.

## Validation status

PASS: offline accelerator before changes, exit 0, including 132 independent
round trips, 15 inert backend ABI, 10 filter ABI and one discard pipeline case.
PASS: 33 focused native renderer/extraction/matrix tests after direct mapping,
exit 0. PASS: final broader 46-test renderer/extraction/pipeline repeat, exit 0,
including all three no-acceptance negatives. Earlier compile/harness failures
and the 35-dot pre-fix mismatch are retained in local diagnostic logs, not
treated as passes.

PASS: full local `bash scripts/ci-swift.sh` at the implementation SHA, exit 0,
bounded to 1200 seconds. 67 Python, 178 Core and 250 Mac tests debug/release,
both accelerator modes, 132 independent round trips per mode, 15 backend ABI,
10 filter ABI and one inert pipeline case per mode, local-ad-hoc ARM/minimum-26
executable/app/nested-worker signature checks and packaged-worker PBM/ZPL equality.
Native host: macOS 26.6.2 build 25G83, Apple Silicon, Swift 6.3.3.
Local artifact: `artifacts/setup-app.7rY2LE/Label Printer Driver Setup.app`.
The separately pinned maintainer manual-check artifact is retained unchanged;
this build does not require repeating or upgrading that finite GUI procedure.
Own hosted CI/review await publication; later evidence edits are source unchanged.

M4-AC13 PASS combines the real three-plan/render/persistence matrix and
preacceptance failures here with the existing four portable reference-workflow
tests, including both unconfigured Letter/A4 definitions refusing guessed crops.
It is strictly an automated reference-workflow result, not installed queues.

Parent PR #68 hosted run 35104542457 passed exact
`4a857a4f8a70768a3d54cad754402eb6f3d9db59`; its first review is clean at base
`3c159cf8565d2e34c86e0d8ab90dbb154e2632ac`. Logs verify 178 Core/248 Mac tests
debug/release and local-signature/packaged-worker PBM/ZPL checks. A separate
pre-change/current version-1 reference encoding check produced identical 1610
bytes, SHA-256 `206f847419818cea55e9104ef5b38ee771412bd44d1974cb3d3d55e9a359edbf`.
That is one actual reference sample, not an all-profiles or physical claim.

## Remaining evidence

M4-AC01 also requires editor/per-job option propagation; this test alone does not
close it. Actual Tahoe application-facing page preservation, workflow selection,
GUI interaction/accessibility, minimum-26.0/offline runtime, scheduler identity
and access, USB, alignment and barcode scanning remain NOT RUN. No queues,
scheduler jobs, hardware commands, clipboard changes or releases occur here.

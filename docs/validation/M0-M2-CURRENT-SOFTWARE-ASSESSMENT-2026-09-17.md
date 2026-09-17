# Current software acceptance assessment — 2026-09-17

Evaluated source:2f1f0e6061885274824e0895fcc6dbe14dea5e48 (local unpublished).
The workspace was clean when finite900-second full baseline46436 started. It uses
process-scoped idle-sleep prevention and process-group timeout cleanup. Baseline passed own exit0:104 Python/281 Core/360 native tests in debug/release,
132 strict/180 compressed independent round trips per mode, finite benchmarks, inert
ABI/pipeline, ARM/minimum26 metadata, nested local signatures, Developer-ID negative and
packaged-worker equality. Final local artifact:artifacts/setup-app.sqj9Kl.
Assessment below is deliberate per-criterion review, not inference from these counts.

## M0-AC03 — Portable package (A pass)

LabelCore Package.swift, library sources and tests were inspected. They do not import
CoreGraphics, AppKit or SwiftUI. Geometry/bitmaps/encoding use portable typed Swift;
the separate CUPS adapter is an explicit C target. Baseline log records Apple Swift6.4,
macOS27 ARM and runs Core debug/release. A Mac run is not a Linux run or a runtime26 test.

## M0-AC04 — macOS package (I pass, native API smoke only)

The current source built natively on local macOS27 ARM with Xcode27/Swift6.4. Actual
CoreGraphicsSmokeCheckTests.testWhitePixel passed in debug/release and the real inert
diagnostic reported255. The implementation allocates a grayscale CGContext, paints white
and reads its byte; it is not a stubbed constant. ARM binaries and minimum26 deployment
metadata were checked. This proves the criterion's local native build/CG smoke, not GUI,
PDF visual semantics, runtime26, installed spooler/helper, retail launch or printing.

## M0-AC07 — Dependency security (A pass)

Both .github/workflows/ci.yml and compatibility.yml were read. All external actions
use full40-hex commit pins; permissions are contents:read; checkout credentials are
not persisted. There are no signing secrets, pull_request_target, self-hosted runners
or privileged install steps. Jobs are finite and standard hosted; superseded runs cancel.
check_repo enforces pins and forbidden triggers/runners. Other clauses were manually
inspected in both workflows and the scripts they actually invoke. The diagnostic and
app scripts sign copies locally and do not install a queue/helper or contact a printer.

## M0-AC08 — Docs and handoff (A pass)

check_repo validates repository-relative links/reference anchors, JSON, four documents
per milestone, matching progress IDs/directories and allowed states. Python preflight
regressions cover stacked PR targets, docs/manifest scope, unknown changes, fenced
examples and image links. This assessment requires actual own-exit preflight/checker
results and semantic progress review; compilation counts do not substitute for them.

## M0-AC11 — Confirmed baseline (A pass)

reference-target.json is explicitly an unqualified planning reference. GC420d/USB,
4×6 pre-cut tear-off/no cutter, MIT, macOS26 minimum and local-ad-hoc mode match the
confirmed baseline. Unit firmware/USB identifiers/URI, sensing, gap/pitch/liner and
printable-region observations stay unknown. Model8dots/mm is separate from nominal203DPI.
Reference tests check exact rounding, seam/padding, wrong model/transport/thermal method,
accessory enabling, unknown gap/speed, false qualification and zero physical budget.
The checked oracle is813×1219 dots/102 row bytes/124338 bytes, not unit measurement.

## M2-AC07 — Compression (A pass)

Two software paths are present: plain ASCII hex and explicit experimental ASCII repeat
counts. Production prepared output remains plain hex; firmware support is not inferred.
No checksum-producing or other compressed family is enabled by this implementation.
ZPLASCIICompressionTests cover literal fallback, additive count boundaries1/2/9/10/19/20/
199/200/201/400/801, repeated-row history reset per band, white padding, exact output budget,
no sink callback on budget/support rejection, sink failure and bounded chunks.

The independent plain and compressed oracles remain separate from Swift encoding.
The compressed oracle independently reconstructs all pixels and band rows, checks padding
and analytic patterns, and includes48 count-boundary vectors. Its malformed tests reject
row-repeat without history, incomplete/overflow expansion, unfinished counts/nibbles,
unsupported fills/symbols, trailing bytes, band-history escape and overlapping origin.
Baseline reported132 plain and180 compressed cross-language round trips per mode.
This is automated encoder/decoder evidence, not firmware, physical print or formal legal
clean-room qualification. No oracle was changed to match the encoder during this review.

## M5-AC12 — Signing-mode separation (A pass)

build-local-app.sh selects local-adhoc explicitly. developer-id fails before building and
never falls back. Nested worker/executable/app signatures are verified separately, with
adhoc/no Authority, ARM and minimum26 checks. The finite full baseline executes both the
negative Developer-ID branch and real local app build/packaged-worker equality.

Separate current-source CLI signature run88261 passed own exit0; local copies are in
artifacts/local-adhoc.T0kngf. Signature validity is not publisher identity, Gatekeeper,
installed helper/spooler admission, retail launch or distribution acceptance.

## Remaining evidence

The successful baseline and semantic reviews now support explicit source/test/evidence
hash binding for the listed criteria. Current historical M3 ledger entries remain
stale after source changes; do not refresh them without independent semantic review.
M5-AC03 routine application printing is not advanced by saved-job inspection/export.
Manual scheduler/GUI/administrator, unit identity/status, physical printer and R evidence
remain separate/open. Frozen Part B unchanged. No merge, publishing, privilege or printer I/O.

An automated native GUI smoke-check attempt against the previously verified local app
returned Computer Use error-10005/cgWindowNotFound twice. Multiple setup instances were
listed with the same bundle identifier. No AX window or screenshot was obtained; GUI
smoke checks remain NOT RUN. No unrelated instance was closed and no UI settings,
installation, privilege prompt or printer action was performed.

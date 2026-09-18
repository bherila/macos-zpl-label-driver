# Explicit automated assessments — 2026-09-17

Evaluated source 9ab1c2f27fbc41081600d9976e0acf69b66d56f4. These two A-level assessments record inspected software behavior,
not maintainer semantic approval, installed printing, hardware receipts or release readiness.
They do not automatically import milestone prose or upgrade another evidence level.

## M3-AC01 — Capability truthfulness (A pass)

PrinterProfile preserves independent model capability, installed hardware and observation
fields. The reference factory keeps unknown model/accessory/current-setting/identity data
unknown while reporting the selected tear-off/absent-cutter configuration separately.
FinishingControlQualification requires explicit enabled mode, supported evidenced mode and
true reported installed accessory; unknown, false, unsupported, missing or wrong provenance
fail rather than silently enable a mode. FinishingJobPlan independently checks exact media
and reported compatible stock. Ordinary profile8 admission remains gated. Tests cover every
mode with unknown/unsupported/unobserved model facts and every accessory with unknown,
false or wrong-provenance observations. No synthetic positive declaration is H evidence.

## M3-AC04 — No implicit persistent mutation (A pass)

Ordinary ZPLPreparedLabelEncoder assembles a closed typed control prefix and canonical packed
raster graphics between fixed format delimiters. ZPLControlEncoder and the closed documented
control enum expose bounded session/format settings, not reset/calibrate/save/erase/firmware
operations or arbitrary raw profile/document strings. Those operations cannot be selected by
ordinary request values. Exact baseline and finishing-fragment negative tests reject the
forbidden command families. Persistent maintenance remains a separately authorized feature;
this assessment does not claim that such a product feature is implemented or privileged.

## Evidence actually run and reviewed

swift test --package-path Packages/LabelCore --filter
'PrinterProfileTests|FinishingControlQualificationTests|ZPLControlEncoderTests' completed
exit0:26 tests, zero failures. Log /tmp/zpl-m3-assessment-focused.log.
The full finite gate previously completed exit0 with103Python/272Core/324Mac debug/release,
including prepared-label and stock-plan regressions; log /tmp/zpl-persisted-finishing-full.log.
git diff42a4cae..9ab1c2f27fbc41081600d9976e0acf69b66d56f4 -- Packages scripts Fixtures .github is empty: executable sources,
fixtures and CI/build inputs are unchanged since that full gate. Code and named negative
assertions were read for these exact criteria, rather than inferred from the test count.

The ledger references exact implementation/test/evidence bytes and this evaluated source.
Only evidence metadata/validation descendants can retain candidate equivalence; changed
code/requirements/build inputs invalidate it. Global M3 integration/H and M6 acceptance
remain open. No admin, device, merge or binary publication action.

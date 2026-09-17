# Current control mapping audit

Inspected local unpublished source `1ad1bc968a2b078355505e7a8e19ea2e420025ed`. This supersedes the missing-control
inventory in M3-CONTROL-COVERAGE-AUDIT-2026-09-17.md for current source; retain
that earlier report as historical evidence. Debug and release LabelCore commands
completed exit0 with281 tests each. This is source/software evidence only.

| Control | Implemented mapping | Qualification and interactions | Test coverage |
|---|---|---|---|
| Print/feed/backfeed | ^PRp,s,b; baseline ^PRp | Tuple parameters explicit; independent speed choices; GC420d print2/3/4 only | ZPLControlEncoderTests, configured defaults/profile codec tests |
| Absolute darkness | ^MD0 then ~SD | Neutralizes additive adjustment; integer0..30 and qualified profile4 fact | ZPLDocumentedControlEncoderTests, configured defaults tests |
| Thermal method | ^MTD/^MTT | Profile7 method evidence and declared consumables; GC420d transfer rejected | ThermalControlIntegrationTests, ThermalControlQualificationTests |
| Gap tracking | ^MNY | Explicit qualified tracking declaration; never guessed from pre-cut stock | ZPLDocumentedControlEncoderTests, PrinterProfileTests |
| Continuous tracking/length | ^MNN then ^LL | One explicit operation; length1..32000 intersects model memory bound; conflicts reject | GeometryControlIntegrationTests, ZPLDocumentedControlEncoderTests |
| Black-mark tracking | ^MNM,offset | Signed conservative range-75..283 intersects qualified range; incompatible continuous length rejects | OffsetControlIntegrationTests |
| Width/home | ^PW/^LH | Independent qualified bounds; explicit home pair; both encoder entry points reject known clipping | GeometryControlIntegrationTests |
| Shift/top | ^LS/^LT | Independent signed fields and bounds; no substitution for label home or mark offset | OffsetControlIntegrationTests |
| Tear-off/cut/peel/rewind mode | ^MMT/^MMC/^MMP/^MMR | Each mode needs independent support/configuration; accessories need observed installation | FinishingControlQualificationTests |
| Cut scheduling and peel waits | Separate qualified framing/delivery path | Schedule uses completed output order; framing quantity1 per raster; waits retain coordination | FinishingJobPlanTests; native finishing framing/coordinator tests in preceding integrated baseline |

The command provenance is recorded in ZPLControlProtocol, the documented
encoder, and qualification types: R45 for the conservative command subset and
finishing modes, R46 for continuous-mode length semantics, R11/R22 for the
reference speed/tear-off subset. This report adds no device commands or source
claims beyond those existing implementations. Protocol bounds alone never grant
installed-unit authority. Persistence/lifetime remains the existing table's
application/session or explicitly unverified model-specific classification;
physical state isolation has not been observed.

Current generic qualification types and versioned profiles cover these software
families; unknown reference darkness, sensing, width/origin, feed/backfeed and
accessories are not promoted by this audit. Normal encoding and the finishing
route remain separate. No reset/calibrate/save/erase/firmware operation is added.

M3-AC03 remains unchecked here: this report repairs an obsolete inventory and
records software mapping; it does not supply a completed per-ID assessment of all
production routes and protocol-table semantics. M3-AC06/07/08/09/10/11 and the
installed system-dialog/default path retain their actual evidence requirements.
A production backend/installer must follow the accepted M1 boundary, which is
still pending. No hardware, scheduler, GUI, administrator operation or publication
occurred. No acceptance ledger pass was created.

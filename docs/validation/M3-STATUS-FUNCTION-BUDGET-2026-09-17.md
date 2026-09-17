# Legacy status function-settings boundary

Advances M3-AC12 malformed status validation; no complete acceptance claim.

Nearest independent constraint: discarded numeric fields still belong to the documented reply grammar. Zebra's public ~HS String 2 table describes function settings as an eight-bit binary value represented by three decimal digits. The decoder previously accepted 256, 511 and 999 and returned a typed snapshot while discarding that field. It now rejects function settings above 255 before constructing a snapshot. The field remains discarded and does not grant installed capabilities or readiness.

Primary provenance: [Zebra ~HS documentation](https://docs.zebra.com/content/tcm/us/en/printers/software/zpl-pg/zpl-commands/~hs4.html), R44. Its indexed field table was refreshed on 2026-09-17. No manual PDF or private status frame is bundled. The interface-settings field has a separate baud-bit table; this fix does not conflate it with function settings or invent limits for unspecified fields.

Regression: testDiscardedFunctionSettingsStillRequireAnEightBitValue accepts 000/255 and rejects 256/511/999 as malformedResponse. Before the fix, the focused swift test command exited 1 with three expected failed assertions. Afterward swift test -c debug/release --package-path Packages/LabelCore each exited 0 with 283 tests and zero failures.

python3 scripts/run-accelerator-checks.py exited 0: repository and fixture checks, 106 Python tests, portable tests/builds, 132 strict bitmap round-trips, 180 compression round-trips, 12 finite CLI cases, 15 CUPS ABI cases, 14 filter ABI cases and one inert discard pipeline. The preceding debug accelerator receipt is the documented-width baseline; neither changes the independent oracle. swift build -c release --package-path Packages/LabelMac --product label-printer-setup exited 0.

No query, printer I/O, queue change, administrator action, GUI test, installed scheduler test, physical label, hosted CI, merge or release occurred. This is unpublished local software evidence. Earlier exact-source acceptance ledger records and the full integrated baseline remain historical after subsequent source changes; no ledger pass was carried forward.

Implementation SHA-256: c107fb9be297ae6eda2a1df002f06a6381224bf6a35c36a21cc7feb3b5fc3ab0

Regression SHA-256: be9a4b3756469ccbaf1a01a28fce58f8f99b3c27f57b336de27ccce8e580eeb8

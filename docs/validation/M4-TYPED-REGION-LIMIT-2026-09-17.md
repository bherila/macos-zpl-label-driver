# Typed workflow page-region admission

Advances M4-AC08 profile safety and M4-AC03 bounded region planning. No full milestone or current-source acceptance pass is claimed.

Nearest independent constraint: the per-page region budget must be consistent across typed profile construction, editor changes and public JSON import. The importer and editor already limited pages to 256 regions. WorkflowPageRule previously accepted 257 or more, allowing typed profiles whose exported JSON could not be reloaded. Typed construction now rejects empty or over-budget extraction regions before profile/planner admission. WorkflowPageRule.maximumRegionsPerPage is shared by all three admission sites. The existing wire schema and 256-region limit remain unchanged; no truncation occurs.

Regression testTypedPageRegionLimitMatchesImportAndBoundaryRoundTrip uses unique synthetic IDs/orders: a 256-region typed profile encodes and reloads exactly; constructing the 257-region rule must throw invalidProfile. Before the fix the focused test command exited 1 with one expected failed assertion. Afterward swift test -c debug/release --package-path Packages/LabelCore each exited 0 with 284 tests and zero failures. swift test -c debug/release --package-path Packages/LabelMac --filter WorkflowEditor each exited 0 with 31 tests and zero failures.

python3 scripts/run-accelerator-checks.py exited 0: repository/fixture integrity, 106 Python tests, portable suite/build, 132 strict bitmap round-trips, 180 compression round-trips, 12 finite CLI cases, 15 CUPS ABI cases, 14 filter ABI cases and one inert discard pipeline. The preceding accelerator receipt is the legacy status boundary validation; the independent oracle was preserved. swift build -c release --package-path Packages/LabelMac --product label-printer-setup exited 0.

No input/output media semantics, label order, copy policy, document payload or rendering source changed. No printer I/O, queue operation, privilege, GUI interaction, merge or release occurred. Native model tests do not prove keyboard accessibility or manual editor behavior. These are unpublished local software results; older full baselines and exact-source acceptance records remain historical. The frozen M1 Part B candidate and physical gates are unchanged.

Packages/LabelCore/Sources/LabelCore/ExtractionPlan.swift: 04ab9dcca4f5582f69c8dfae80c98970b1bba78edd482d622673f54afdd3242d

Packages/LabelCore/Sources/LabelCore/WorkflowProfileDraft.swift: 3d6c6852a2d5a604a7a73e9a94901eb652b81e71de00dcaf32c822e803bac0f0

Packages/LabelCore/Sources/LabelCore/WorkflowProfileJSON.swift: 10d1f67d0a4f24a623b38ef76f3195935fa9c688ba874668c93c87a3cc36506d

Packages/LabelCore/Tests/LabelCoreTests/WorkflowProfileJSONTests.swift: c9839efb68ead21e21458754ef29eb525a40a07d8f51692e9be4ef413279b5ed

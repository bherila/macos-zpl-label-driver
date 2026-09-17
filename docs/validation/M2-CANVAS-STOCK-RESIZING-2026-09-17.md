# Canvas stock resizing — 2026-09-17

Source checkpoint: `8749143c93c3f9ad2c038325de5848e66b2f1287` (local, unpublished).

DotCanvas now retains its original width, height and packed-byte admission limits. replacingPhysicalSize rebuilds validated geometry using those limits and the same independent X/Y dot pitch. It never increases budgets. Equality explicitly preserves the pre-existing rendered-geometry contract, excluding admission budgets; this avoids changing finishing binding comparisons that reconstruct canvases with different budgets.

Regression: unequal pitches, smaller destination, repeated resize back, independent width/height errors, and a combined packed-byte overflow with individually permitted dimensions. Same geometry with different budgets remains equal, while only the permissive canvas can admit the larger combined allocation. Source canvas remains immutable. This adds a new API; no before-fix behavioral failure run is claimed.

Validation: preliminary full Core debug/release suites passed 305 tests each. Accelerator passed 106 Python/305 debug Core tests plus 132 strict/180 compression/2 privacy/12 CLI/15 ABI/14 filter/1 inert discard cases, own exit0. These preceded final explicit equality and stronger exact byte-error assertions. Final PhysicalGeometryTests passed all9 debug/release, own exits0. Logs: /tmp/zpl-canvas-retained-limits-{debug,release,accelerator,final-debug,final-release}.log. Diff check passed.

Native/GUI/signature/Linux/scheduler/administrator/physical tests NOT RUN for this slice. Prior native baseline remains historical. Native stock editor integration is still pending; this API supplies limit-preserving rendering context only, with no physical stock qualification or acceptance-ledger refresh. No queue/device/privileged operations, merge or publication. Frozen Part B candidate unchanged.

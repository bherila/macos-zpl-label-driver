# Documented print-width bounded-subset fix

Standalone documented print-width encoding now enforces the same2..32000 bounded geometry subset for both requested width and supplied model maximum. Overbroad declarations reject rather than widen the subset. New regression reproduced7 expected failures before the fix;282Core tests passed debug/release afterward;106Python tests, release setup-app build and debug accelerator passed exit0. No hardware/control setting changed. Older exact-source ledger records are historical after this source change; no acceptance refresh.

Nearest independent constraint: a model/label declaration must intersect the
implementation's supported geometry domain, rather than widen it. Ordinary profile
qualification already bounds declarations at32000; standalone printWidth previously
only checked value>=2 and value<=suppliedMaximum, allowing an Int.max declaration.
The fix checks both values within2..32000 before constructing any fragment.

The regression enumerates supplied maxima32001/Int.max against widths2/32000/
32001/Int.max, plus exact valid edges and a smaller model maximum. Before the fix
seven XCTAssertThrowsError assertions failed. Afterward all282Core cases passed in
debug and release, including existing geometry/clipping and other control tests.
Release setup-app build passed exit0. Required accelerator follow-on passed132strict
and180compression round-trips,12finite CLI cases,15CUPS ABI,14filter ABI and one
discard pipeline; its included repository/Python checks passed. The preceding
integrated baseline is before this change; it is not a current full Mac suite claim.

Zebra's public ^PW reference bounds width by the label and describes printer-side
clamping above that width:
https://docs.zebra.com/content/tcm/us/en/printers/software/zpl-pg/zpl-commands/%5Epw.html
The32000 ceiling here is explicitly the project's conservative geometry subset,
not a universal protocol ceiling or observed installed label/head width. No raw
printer payload was delivered, device queried, setting persisted, queue changed,
privilege used, manual GUI tested, source pushed or binary published.

Evaluated implementation digest: 0160e5c33772c6a516e2d729d98e5ee9dddae475b86e418e72c40abb270a3674
Evaluated regression digest: 230b8c20595ada42fa3b650afb79d91db249aaeefc6327ce6f02a47b3256ccb9

Current per-ID source-bound records become historical after the code/test change;
do not mechanically carry prior M3-AC02 assessments forward. The wider declaration
case must be included in any fresh semantic assessment. Manual gates remain unchanged.

Local implementation checkpoint: `8dcc24141aaa8dbb6ca6aa27aecba0ba9193267b`; committed implementation/regression bytes match the tested digests above. This is unpublished, not a hosted CI/review claim.

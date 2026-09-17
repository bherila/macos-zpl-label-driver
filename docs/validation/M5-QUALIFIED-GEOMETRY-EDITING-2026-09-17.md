# Qualified physical geometry draft editing — 2026-09-17

Partial implementation evidence for M5-AC04/10 and M3-AC02/03/11. No integration
acceptance is checked by this automated slice. Source is currently unpublished.

## Constraint and behavior

A partial geometry edit must preserve independent configured width, length and
home fields, while invalid text must never become inheritance or a clamped value.
Tracking and continuous length remain a validated combination. Draft selection
never changes a device, immutable profile or loaded-stock declaration.

The setup model/view exposes only independently evidenced schema-5 geometry
ranges. Width/continuous length/home X/home Y have dot units, minimum/maximum
hints, configured-default placeholders and blank-to-inherit behavior. An explicit
home coordinate of zero is different from blank. Each nonblank field must parse
as a bounded whole number; malformed, fractional, non-finite, overflowing,
negative or out-of-range text stays visible and blocks workflow/default readiness.
Both home coordinates must resolve together; continuous mode needs a qualified
length. Gap mode cannot silently discard an inherited continuous length. Returning
to configured tracking defaults preserves the bound profile combination.

Gap and continuous tracking appear only with supported evidenced profile facts.
Black-mark tracking remains unavailable pending offset qualification. Geometry
facts distinguish configured qualification, unavailable and unknown current state.
The reference GC420d profile exposes no new geometry/tracking controls. Existing
motor/darkness choices and immutable defaults are preserved. No new target,
printer command, profile-file write, installation or queue action is introduced.

## Validation

`swift test --package-path Packages/LabelMac --filter ReferencePrinterSetupTests`
passed exit0 with 19 tests. Five new cases cover independent inheritance/explicit
zero, every invalid field class, tracking/default length conflicts and reset,
unqualified reference rejection, and incomplete home/continuous-length recovery.
Existing 14 cases remain, including motor/darkness preservation. A declared
qualified continuous profile is synthetic evidence, not an observed printer.

The full finite 900-second `bash scripts/ci-swift.sh` gate passed with its own exit0: 89 Python, 231 Core and 290 Mac tests in debug/release; 132 original and 180 ASCII independent round trips, 12 finite benchmark CLI cases, inert ABI/pipeline harnesses, native ARM/minimum26 metadata, nested ad-hoc signatures and exact packaged-worker PBM/ZPL equality. Local artifact: `artifacts/setup-app.jTKLCU`. No GUI/keyboard/VoiceOver walk-through,
installed system dialog, Tahoe 26 host, USB or physical output was run in this slice.

## Remaining gates and next step

Push the reviewed source slice on existing PR81 after the previous exact-head hosted run terminates; do not cancel that validation for this checkpoint.
Native profile import/save and complete workflow/default management remain work;
these session drafts are not persistent printer settings. Blank inherits a value; clearing an inherited continuous length is not represented by this draft API, so changing to gap fails explicitly rather than removing that length. Black-mark offset,
shift/top, thermal/finishing integration and model qualification remain work.
M1 adapter/helper/install design requires real scheduler evidence. Part B retains
its approved frozen candidate and single-discard-job budget. No merge/binary release.

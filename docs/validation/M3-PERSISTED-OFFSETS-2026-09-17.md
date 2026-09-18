# Immutable offset control persistence and placement — 2026-09-17

Partial implementation evidence for M3-AC02/03/11, M2-AC08, M4-AC12 and
M5-AC04. Source published on PR81; no manual acceptance completion.

## Independent constraint and version contract

Every effective offset must survive canonical private persistence and immutable
acceptance/preparation. A partial top edit must retain independent shift and
mark offset. Offset qualification cannot become a guessed zero/model interval;
signed placement must not pass known clipping merely because the unshifted raster
fits. This slice connects the previous independent offset policy to ordinary jobs.

Profile6 adds required `capabilities.offsets` with exact `blackMark`, `shiftLeft`
and `labelTop` objects, each containing `fact`, nullable `minimumDots` and nullable
`maximumDots`. Supported intervals require both endpoints and independent evidence;
unknown/unsupported intervals have both endpoints null. Reversed, partial,
Boolean, extreme and platform-outside declarations fail before range construction.
Configured defaults have required nullable `offsets` with exact nullable
`blackMarkOffsetDots`, `shiftLeftDots` and `labelTopDots`. Queue5 has the same exact
nullable default shape and can bind profile6. Ticket6 has a required offset setting
object (`mode`, `value`) and admits queue1–5/profile1–6 in their respective slots.
Previous versions retain their exact shapes and cannot admit these new controls.
Future versions/downgrades fail; generic reference maxima do not widen queue slots.

Offset fields resolve separately: explicit job, workflow, configured profile.
Mode/mark offset are a validated pair; gap/continuous cannot retain a mark offset,
black-mark needs an explicit qualified offset (zero is allowed), and sensed modes
cannot inherit a continuous length. The encoder emits width/home and offset controls
before graphics/first field separator. Prepared jobs reject mixed effective offsets,
even when byte lengths are identical. Factory reference profile stays unchanged.

## Known signed placement and provenance

Both public preparation and direct encoding use the same known-raster check before
graphics allocation. For known home X and explicit shift, effective X is home minus
shift; for known home Y and explicit label top, effective Y is home plus top.
Reporting-overflow arithmetic rejects overflow/negative known origins. Controlled
width/continuous length use guarded subtraction for known far-edge containment.
A positive left shift can bring a known home back to zero; it is not added to home.
Unknown home/shift/top/width/sensing/media/device state is still unknown; this check
is necessary packed-data containment, not a physical printable-area proof.

R45's cached public programming guide hash was reverified as
`b1f83b0822f176bb20b7cfe14a37ea33fb552c3d6bcf05da1b4c2704ad3aaa0c`.
Its command table defines `^LS` as shift left and `^LT` negative toward the top /
positive away. Current model-specific user-menu descriptions of horizontal offsets
can use opposite sign wording; these menu/SGD descriptions are not substituted for
the direct ZPL command specification. The guide also warns that label-top front-panel
values may differ from ZPL and negative top movement can have mechanical effects.
No menu default, omitted offset, physical response or device setting is inferred.
The primary guide is referenced, not committed; no proprietary driver inspected.

## Validation

Corrected Core suite passed exit0:242 tests, including five new offset integration
cases plus queue5/ticket6 immutable/default/forgery coverage. Five earlier offset
policy cases remain. Existing future-version tests now target7; malformed version6
fields are directly covered rather than lowering acceptance. The first upgrade
run's three obsolete version-boundary expectations failed before these changes.

Focused native/setup selection passed exit0:21 tests (20 setup plus original-PDF
inert offset pipeline). Two source regions retain stored ticket6/profile6/queue5
controls exactly through prepared output. Both include inherited explicit shift0
and workflow top1 rather than configured top0. Motor/darkness/geometry controls
remain bound; source original PDF and production pitch/model guards are retained.
Qualification is synthetic, not observed model/unit settings. No printer reached.

Full finite 900-second `bash scripts/ci-swift.sh` gate passed ownexit0:89 Python/242 Core/292 Mac debug/release,132 original and180 ASCII independent round trips,finite benchmark/inert ABI/pipeline harnesses,ARM/minimum26 native products,nested ad-hoc signatures and packaged-worker PBM/ZPL equality. Local artifact:`artifacts/setup-app.NOdSeq`.

The deliberate ignored-offset containment fault failed exit1 (one regression case, nine assertions: missing clipping rejection at both entry points and incorrect rejection of a positive shift that cancels home). Prepared encoder restored byte-for-byte with hash equality; complete restored Core suite passed242 tests exit0. The full-gate source bytes and restored source are equal.

## Remaining work and gates

Utility offset selectors and persistent native default/profile management remain
implementation work, as do thermal/finishing policy integration. Setup edits now
retain bound offsets and schema6 geometry qualification. Black-mark mode can only
be used with a qualified bound offset; missing offset receives an explicit error.
No model/hardware support row is widened. Installed adapter/system dialog, helper
identity/lifecycle, actual sensing/stock, USB, alternating physical state and fault
recovery require prescribed evidence. Part B retains its frozen approved candidate.
No administrator/queue/printer action, physical label, merge or binary publication.

## Source checkpoint

Remote branch/PR81 head read back at `272fc90690490c3ffe030999f79cb464635de444`. Hosted run35215154447 observed in progress, not pass evidence. Preceding64272f0 run35214380345 passed exact source before this push.

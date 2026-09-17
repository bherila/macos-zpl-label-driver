# Immutable physical geometry and tracking — 2026-09-17

Additional partial M3-AC02/03/11, M2-AC08, M4-AC12 and M5-AC04 only.
No installed scheduler, physical state isolation or complete control acceptance.

## Independent constraint

All effective physical fields must survive canonical configuration and immutable
acceptance/preparation, with explicit mode/length pairing and known containment.
A partial origin edit must not replace independent width/length defaults. Neither
PDF geometry nor nominal stock authorizes device controls or model memory bounds.

## Implementation

Profile5 adds separately evidenced physical width/continuous-length/home-X/home-Y
qualification and nullable tracking/geometry defaults. Every supported bound needs
explicit evidence; unknown and unsupported retain nil bounds and distinct states.
The geometry subset is width2..32000, continuous length1..32000 and home0..32000,
further limited by independently supplied model maxima. Earlier canonical profile
formats stay exact and cannot accept the new qualification/default fields.

Queue4 adds required nullable tracking/geometry defaults and may bind profile5.
Its validation resolves effective defaults, allowing partial workflow values only
when the bound profile supplies the complete valid combination. Earlier queues
cannot bind the new profile or accept new fields. Preliminary reference discovery
recognizes the actual queue format and full decoding validates against the exact
immutable profile. Ticket5 admits profile5/queue4; earlier tickets reject new
references/tracking/geometry. Reference slots have kind-specific version limits,
so profile5 support does not imply a queue5 format.

Physical width, length and each home coordinate resolve independently: job,
workflow, then configured profile defaults. The effective home must be complete.
Qualified gap mode emits ^MNY; continuous mode requires positive model-bounded
length and emits ^MNN then ^LLn. Sensed-media length and black-mark offset mapping
remain unavailable; no default offset is guessed. Conflicting mode/default length
fails rather than silently dropping the length. R45/R46 document commands and the
retained optional length-scope flag; later gap/mark scope is not normalized.

The ordinary encoder emits width and complete home before original packed graphics
and first field separator. Both prepared and direct bitmap encoding call the same
necessary known raster containment guard before graphic generation. Requested
extents must fit the raster and known home components without overflow. Unknown
shift/top/device settings and stock-versus-printable extent remain distinct; this
is not sufficient physical placement or state-isolation proof. Same-length labels
with differing physical controls cannot enter one prepared job.

The setup model retains effective tracking/geometry while editing another default,
preserves profile5 qualified darkness and labels configured tracking separately
from unknown current state. This is automated default integration, not full
geometry selectors/system-dialog/accessibility acceptance. The reference factory
profile remains unchanged and cannot emit these newly qualified controls.

## Validation

231 Core tests passed: six geometry integration cases, the complete queue/ticket
case and all earlier coverage. Canonical profile/queue/ticket round trips, malformed
Boolean/missing/extreme fields, every bound, downgrade/future rejection, precedence,
mode/length conflicts, both clipping entry points and mixed-control jobs are covered.

The whole-object-precedence variant reproduced continuousLengthRequired (one
unexpected failure, exit1), proving that partial origin edits lose independent
settings without the per-field resolver. Source restored. A valid generic profile5
reference inserted into the queue slot initially failed to throw (one failure,
exit1); the kind-specific bound now rejects it. Original coverage retained.

Fifteen focused native/setup tests passed: fourteen setup cases and the new
original-PDF two-label inert pipeline case. Stored profile5/queue4/ticket5 controls
match final prepared controls; both formats carry workflow length1300/width813
rather than different synthetic configured1400/832, plus explicit home0,0. Both
retain qualified motor/darkness defaults. Inert transmitted count matches the
complete prepared bytes. Qualification/numbers are synthetic, not observed unit
memory, settings or continuous-media support. Production model/pitch guard stays
unchanged. Corrected `bash scripts/ci-swift.sh` gate passed with its own exit 0: 89 Python, 231 Core and 285 Mac tests in debug/release, accelerator and independent checks, finite benchmark/inert ABI harnesses, native product ad-hoc signatures and ARM/minimum macOS 26.0 metadata. Packaged worker synthetic PBM/ZPL equals the release worker. Local artifact: `artifacts/setup-app.5Dyzgh`. These results do not establish installed scheduler or physical output.

## Remaining work and gates

Full utility geometry selectors/system dialog, black-mark offset, shift/top,
thermal/finishing policies and model qualification remain implementation work.
Actual adapter/USB/helper identity/lifecycle follows M1 admission. Installed and
physical media/state/fault recovery require prescribed finite evidence; no command
was sent to a printer, no queue/admin action, no merge/binary release. Part B remains
its separately frozen bytes. M3-AC03 and applicable manual acceptances stay unchecked.

# Offline continuous tracking and length fragment — 2026-09-17

Additional partial M3-AC03/04/12 only. No ordinary profile/queue/ticket admission,
physical media switch, GUI, scheduler or unit qualification is established.

## Constraint and implementation

A continuous tracking request must include an explicit label length, rather than
using retained length or guessing missing model memory. R46 records public primary
mode/length/scope semantics and direct-fetch limitations. The command type pairs
both settings atomically: continuousTracking(labelLengthDots) emits ^MNN followed
by ^LLn. These commands are intended before the first field separator in a format.
The fragment emits no ^FS or envelope and does not certify a caller's placement.

The optional modern length scope flag is retained; either documented Y or N
applies to explicitly continuous media, so current-format applicability does not
depend on its unknown value. No delimiter is guessed for a second argument.
Later gap/mark scope is not normalized or declared unchanged. This is a narrowly
specified continuous operation, not general label length for sensed stock.

Explicit supported command qualification and a provided model maximum are both
required. Requested length and maximum must be1..32000, with the request within
that model memory/label-size limit. Nil/zero/infinite-style limits fail. Gap,
mark and continuous modes conflict pairwise; no contradictory fragment is returned.
Duplicates, total command count and complete output budget remain bounded.
No calibration, save, reset, media sensing observation, cutter or printer I/O.

## Validation

Seven focused fragment tests passed. New cases check lengths1/1219/32000, exact
paired bytes/order and output budget, unknown/unsupported qualification, model
and protocol limits, missing maximum, both competing modes and twelve-kind count
bound. The existing complete-kind qualification enumeration initially failed when
the new kind was absent from its test inputs; it was extended to include the
continuous operation rather than removing that coverage assertion. The initial
full run stopped red at that coverage failure. Corrected full `bash scripts/ci-swift.sh` passed exit0 under900-second timeout
on local macOS27 ARM: 89 Python / 219 Core / 283 Mac debug/release, both132 original and180 ASCII round-trips, twelve benchmark CLI cases, fifteen inert ABI cases, native builds, nested local-ad-hoc signatures, ARM/minimum26 metadata and packaged PBM/ZPL equality.
Tracked/changed disclosure scan and manual diff review passed.

## Next integration and remaining gates

Ordinary profiles1..4 still reject tracking and geometry. Next coherent versioned
slice must represent qualified physical geometry/model memory limits, capture
tracking/length/defaults in profile/queue/ticket, enforce the paired resolution
and place these controls before original packed graphics. Width/home/shift/top
need independent range/interaction validation; a nominal label face or PDF box
never authorizes physical controls. Protect against clipping by comparing the
prepared raster with explicitly controlled physical dimensions. Do not introduce
an encoder-only production path or ignore a requested length on sensed media.

Factory continuous tracking remains unknown. Physical state isolation, supported
firmware semantics and actual media behavior require prescribed finite evidence.
Frozen Part B remains unchanged. No manual acceptance/support row is promoted.

# Physical geometry qualification policy — 2026-09-17

Additional partial M3-AC02/03 and M2-AC08 only. No ordinary profile admission,
installed queue, physical origin/length/width or state-isolation acceptance.

## Independent constraint

Every explicitly requested physical component needs its own model qualification
and bound, and the resolved operation must cover every supplied component. A
PDF box, nominal stock face or unknown current setting does not authorize a
physical width/length/home command. Missing values are not zero or unlimited.

## Implementation

QualifiedDotLimit carries a fact and nullable maximum. PhysicalGeometryQualification
keeps separate width, continuous-length, home-X and home-Y declarations. Supported
limits require non-unobserved evidence and a maximum in the implemented bounded
subset; unknown/unsupported require nil bounds while retaining distinct states.
Width minimum2, length minimum1 and home minimum0 are distinct. The32000 ceiling
is this implementation's geometry resource subset, not a universal printhead claim.

Typed requests reject empty geometry, a half-specified home, out-of-range values
and unavailable components. Continuous length requires explicit continuous mode
with supported evidenced qualification; continuous mode without a length fails.
Lengths on gap/mark/unspecified modes fail rather than being discarded. Resolution
produces the paired continuous operation, width and complete home in stable order.
An offline encoder bridge applies existing R45/R46 qualified command/output bounds.
No profile string, PDF geometry, current-setting query or printer transport enters.

Known raster containment is a separate necessary condition. Explicit width/length
must contain packed dimensions and any known home component; guarded subtraction
avoids overflow even for a home beyond the controlled extent. Unknown home and
other shift/top/device settings remain unknown. Selected stock extent and printable
extent remain distinct from command model limits; this is not sufficient physical
placement proof. The fragment bridge has no raster and cannot certify containment.
Final preparation must call the raster validator in the next integration slice.

## Validation

Five focused tests passed: exact paired bytes/order and complete output budget;
all declaration states/evidence/limits; independent width/home rejection;
continuous mode/length/model pairing; and known containment with nonzero home,
exact-fit boundaries and home beyond extent. Initial compile used bitmap fields
on the wrong level; corrected to checked BitmapLayout dimensions before successful
focused validation. Full `bash scripts/ci-swift.sh` passed exit0 under900-second timeout on local
macOS27 ARM: 89 Python / 224 Core / 283 Mac debug/release, both132 original and180 ASCII round-trips, twelve benchmark CLI cases, fifteen inert ABI cases, native builds, nested local-ad-hoc signatures, ARM/minimum26 metadata and packaged PBM/ZPL equality.
Tracked/changed disclosure scan and manual diff review passed.

## Next coherent integration

The new policy is an offline reusable component, not ordinary profile5 admission.
Persist these facts/bounds in the next strict profile format; add nullable geometry
and tracking defaults with complete queue/ticket versions and immutable binding.
Resolve physical fields per job/workflow/configured precedence, then validate the
complete home and mode/length combination. Do not treat a partial geometry object
as permission to silently drop independent configured physical fields.

Ordinary encoding must place controls before first field separator and prepared
original raster; preparation must reject requested extents that clip the known
packed raster. Preserve legacy canonical bytes and unknown reference capabilities.
Need per-field malformed/downgrade/default-loss regressions, complete two-label
inert persistence and immutable mixed-setting rejection. Shift/top/thermal/model
finishing policies remain separate controls requiring their own evidence.

Sensed-stock length, physical state isolation, actual printer memory/model bounds,
USB/accepted adapter and installed/GUI evidence remain open. Part B stays frozen.

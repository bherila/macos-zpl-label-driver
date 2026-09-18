# Qualified absolute darkness persistence — 2026-09-17

Additional partial M3-AC02/03/11, M2-AC08 and M4-AC12 only. No physical
state isolation, scheduler, installed controls or manual utility evidence.

## Independent constraint

An explicit absolute darkness value must survive immutable profile and queue
persistence, bind acceptance and preparation identically, and neutralize relative
adjustment before encoding. Unknown current state is not zero or a factory value.

The old-code four-test regression reproduced three unexpected unavailableDarkness
failures. After preliminary admission/encoding, the existing profile serializer
silently omitted the configured darkness field; its round-trip regression failed
two assertions, including producing only the legacy tear-off bytes. This feature
was restructured before publication to version the persistence contract.

## Implementation

Profile4 adds a required nullable configuredDefaults.darkness integer, preserving
profile1/2/3 canonical formats. Feed/backfeed objects/defaults from3 remain required
in4. Explicit darkness requires profile4, a supported darkness capability and
non-unobserved evidence. The integer subset is0..30 with no clamp. Legacy versions,
unknown, unsupported and supported/unobserved requests remain unavailable.
Factory GC420d profile/facts are unchanged; documented device-default numbers
are not read-only unit observations.

Queue3 adds a required nullable defaults.darkness integer. Earlier queues reject
that field and cannot bind profile4. Preliminary reference discovery recognizes
queue3, but full bounded decoding still validates the entire definition against
the exact immutable profile. Ticket4 admits the new references; ticket2/3 cannot
be downgraded to admit new controls/references. Existing darkness ticket fields
capture the effective value and full decoding re-resolves against bound defaults.
Job choices override workflow defaults, which override configured defaults.

The ordinary encoder shares R45 public protocol mapping: ^MD0 followed by ~SDnn
with two-digit0..30. This normalizes additive relative adjustment rather than
assuming existing device state. Output limits apply to the complete result.
No save/reset/calibration/erase/firmware command, queue mutation or printer I/O.
A configured absolute value can affect later jobs until replaced; physical
state isolation across profiles still requires prescribed printer evidence.
Prepared jobs reject same-length labels with different darkness controls.

## Validation

Seven focused Core tests passed: all31 integers and output budgets, precedence,
immutable preparation, qualification/legacy rejection, canonical profile4 round
trip, malformed/missing/downgraded persistence, mixed-job rejection and bound
queue/ticket round trip with dropped effective darkness rejection.

The native synthetic original-PDF test passed with bounded4KiB writes. Two labels
use workflow20 rather than different synthetic configured10, and both use the
same independently qualified motor tuple. Private profile4/queue3/ticket4 load,
resolved controls, prepared command counts and inert transmitted count agree.
These fixture numbers/qualification are synthetic, not observed device settings.
The initial seven-byte chunk variant was stopped while consuming excessive CPU;
it is not pass evidence. Dedicated existing transport tests retain tiny short
write coverage; the control integration uses the existing finite4KiB budget.

Full `bash scripts/ci-swift.sh` passed exit0 under900-second timeout on local
macOS27 ARM: 89 Python / 217 Core / 279 Mac debug/release, both132 original and180 ASCII round-trips, twelve benchmark CLI cases, fifteen inert ABI cases, native builds, nested local-ad-hoc signatures, ARM/minimum26 metadata and packaged PBM/ZPL equality.
New artifact `artifacts/setup-app.BYgrdF` is built/signature-verified, not manually
tested. Tracked/changed disclosure scan and manual diff review passed.

## Remaining gates

Real qualified utility controls/system dialog, USB/coordinator integration,
installed scheduler, physical value quality and alternating-profile state
isolation remain NOT RUN. Reference darkness support/current value stay unknown.
M3-AC03 remains unchecked: tracking/media/offset/thermal/finishing coverage and
model qualification are not completed by this feature. Part B is frozen unchanged.

Published source `83cfaa8de97fe933f7884d79d63b64add8dc49dc`; remote branch/PR head read back
exact. Hosted35209283943 queued, not yet pass evidence.

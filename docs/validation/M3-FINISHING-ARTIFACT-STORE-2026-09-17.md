# Private immutable finishing archive publication — 2026-09-17

Partial software prerequisite for durable finishing preparation/recovery, not accepted
spooler admission or post-crash replay. FinishingArtifactStore reuses the existing
PrivateImmutableDirectory ownership, no-follow, regular-file, atomic exclusive rename,
file/directory durability barriers, publication lock and exact idempotent reconciliation.
The helper now has a closed JSON/binary record format; existing callers default to JSON.
Capacity counts the selected record extension under the same publication lock, and capped
publishers require matching filenames. This avoids treating binary archives as zero records.

Archives are bounded to96MiB, capped at four committed records per archive directory
(384MiB), stored under opaque hashed selector names. FinishingArtifactReference is distinct
from profiles/tickets and validates identifier/revision/digest using the existing bounded
validator. Save serializes the independently sealed framed output; conflicting bytes never
replace an existing revision. Uncertain publication returns the exact reference for explicit
readback and does not automatically retry. Cancellation before publication is cancelled;
after publication it reports uncertainty with the selector. Cold load requires the exact
reference plus independently reconstructed framed context and verifies canonical archive
bytes and digest. It never enumerates/replays jobs, manufactures status, or accepts a device.

Nearest independent constraint: format-specific capacity admission and immutable readback
must remain true together, including exact idempotent reconciliation at a full store.
Nine actual original-PDF/all-mode native focused cases passed ownexit0, covering cold reopen,
exact retry, same-selector changed-context conflict preserving original bytes, wrong digest,
post-rename sync uncertainty with exact readback, four-record admission/fifth rejection,
idempotent full-store retry and unsafe identifiers. Reverting capacity counting to JSON-only
failed four assertions ownexit1. Restored38combined native cases passed ownexit0 across
finishing, printer-profile and workflow-profile stores. Restored shared source SHA256
2ff92a230c261da1daf44d99fd9e4d75832cc46e9f81d503873fe000930166b2;
new store SHA256 b7342cc035106edaddbe32490111fdc8937d220042a7a2b30260c3e6859bebd1.
Logs /tmp/zpl-finishing-store-focused.log, /tmp/zpl-finishing-store-capacity-fault.log,
/tmp/zpl-finishing-store-restored.log. Full finite900s session57062 completed FULL_GATE_EXIT 0:89 Python/272 Core/324 native
debug/release tests;132 strict/180 ASCII oracle round trips per mode; finite benchmark,
inert ABI/pipeline, ARM/minimum26 metadata, nested local ad-hoc signatures, unavailable
Developer-ID negative and packaged-worker PBM/ZPL equality passed. Artifact
artifacts/setup-app.geRkBj; log /tmp/zpl-finishing-store-full.log. No printer accessed.
Manual source review and tracked/new disclosure
scan passed; both restored source hashes remain unchanged. Typed capped filenames
match capacity counting, idempotent reconciliation precedes capacity admission, and
all uncertainty selectors retain exact bytes/digest context. Exact hosted coverage of this local store slice remains pending.

Published serialization checkpoint60257d1 follows verified hosted success35233437806 at
eafb564. That earlier hosted result does not cover serialization or this local store slice.
Remaining: accepted original-source/profile/queue/device/pitch binding, durable lifecycle/
restart inventory and conservative uncertain recovery, actual bounded file/status provider
and lease lifetime, scheduler retry behavior and physical qualification. A stored archive
is not device-write authority. Ordinary schema8 remains gated. Frozen B unchanged.
No administrator/printer/merge/binary publication action.

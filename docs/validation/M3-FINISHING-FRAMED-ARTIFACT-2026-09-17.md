# Bound finishing artifact serialization — 2026-09-17

Partial software prerequisites for M3-AC09 and immutable prepared-artifact recovery;
not accepted-store publication, restart recovery or device-write authority.
FinishingFramedArtifact emits a version1 domain-separated binary archive with fixed
UInt64 little-endian scalars and length-prefixed UTF8/blob fields. It retains the exact
profile reference and canonical full profile, source hash/count, complete ordered
extraction labels and accounted skipped pages, original/normalized crop rectangles,
rotation/fit/stock/profile identity, physical canvas and resolution, monochrome policy,
ordered packed-raster binding, selected mode/count/cut schedule/boundaries, normalized
control bytes, additional qualification states/evidence and file observation, total
encoded bytes, and separately tagged ordered format/cut files and status requirements.
Finite geometry preserves IEEE754 bit patterns rather than decimal approximations.
No format/cut file concatenation can erase file/status boundaries.

Archives have a1–96MiB aggregate cap (64MiB output plus bounded context/step overhead),
32KiB per-string metadata cap, checked remaining-capacity appends and finite positive
at-most60s encoding/reopen deadline with cancellation. Reopening requires independently
supplied immutable framed context and exact canonical byte equality. External lengths
or counts never drive parsing/allocation. Unknown versions/fields, corruption, missing/
trailing bytes and changed order/context fail comparison. Comparison and hashing remain
inside the total budget. SHA256 is integrity metadata, not publisher authentication.
No decoder manufactures a job from archive bytes. These artifacts contain private
in-process context and must not be general diagnostic/log payloads.

Nearest independent constraint: identical encoded files do not prove identical original
source/provenance. The real original-PDF all-mode fixture changes only sourceSHA while
retaining all rasters/steps and requires rejection. Omitting source hash from serialization
failed four assertions ownexit1. Byte-restored nine focused native cases passed ownexit0.
Other coverage: deterministic archive/digest, exact cap and one-byte short cap, empty,
truncated, trailing and bit-corrupt input, reversed step order, cancellation and exhausted/
invalid deadline. Restored source SHA256
54b83059fd8cce64c0b65ba99f42b3ab70a11975c81563e0b288a72c13b3823c.
Logs /tmp/zpl-finishing-artifact-focused.log, /tmp/zpl-finishing-artifact-source-fault.log,
/tmp/zpl-finishing-artifact-restored.log. Full finite900s session1032 completed FULL_GATE_EXIT 0:89 Python/272 Core/324 native
debug/release tests;132 strict/180 ASCII oracle round trips per mode; finite benchmark,
inert ABI/pipeline, ARM/minimum26 metadata, nested local ad-hoc signatures, unavailable
Developer-ID negative and packaged-worker PBM/ZPL equality passed. Artifact
artifacts/setup-app.hSSAIH; log /tmp/zpl-finishing-artifact-full.log. No printer accessed.
Manual source review and tracked/new disclosure
scan passed; restored artifact source hash remained unchanged. Capacity subtraction
is safe because every append preserves data.count<=maximumBytes, and every external
archive is compared rather than decoded. Exact hosted coverage of this local artifact slice remains pending.

The existing ordinary artifact store requires an accepted ticket and single ordinary
payload; schema8 finishing admission remains gated. Next: accepted exact-context binding,
private immutable archive publication and conservative durable lifecycle/restart recovery,
then actual bounded file/status/lease integration. Do not deserialize these archives into
an automatic replay path. Frozen B unchanged. No administrator/printer/merge/binary action.

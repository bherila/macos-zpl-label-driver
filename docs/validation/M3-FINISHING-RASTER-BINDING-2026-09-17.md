# Ordered packed raster inputs for finishing intentions — 2026-09-17

Partial M3-AC02/03/11 implementation. No mechanical delivery or original-source proof.

FinishingRasterBinding retains the exact ProfileBoundFinishingJobPlan and hashes
its complete ordered packed raster input list. Domain-separated leaf hashes frame
width, height, row stride and byte count as fixed-width little-endian UInt64 values,
then actual packed bytes. The ordered digest frames count, ordinal and each leaf
hash, so reordered labels, changed pixels and changed dimensions cannot substitute
merely because byte counts match. Public identity metadata remains immutable.
Validation compares the whole bound profile/mode/schedule/count context before
recomputing raster identities and order. It does not rerender or retain another
payload copy; per-label temporary hashing input is bounded. A sender must capture
and validate the actual immutable inputs it uses, not a separately supplied hash.

Limits follow the existing project resource caps:1 byte–512MiB total packed bytes,
8192 width/65535 height and32Mi pixels per label. Arithmetic reports overflow;
invalid limits/counts/geometry fail before hashing that input. Cancellation checks
between bounded labels and before returning. Identical raster copies are permitted;
copies/ranges remain owned by the engine. Hashing does not establish original-PDF
provenance, encoded-command equality, physical stock fit or transmission authority.
Ordinary profile8 resolution/encoding remains rejected pending mechanical integration.

## Automated evidence

Seven focused native cases passed ownexit0 (three new raster cases plus four existing
profile-plan cases). New cases cover original validation, reordered/replaced/reshaped
same-byte inputs; independent count/byte/width/height/pixel limits and cancellation;
and changed profile/mode/schedule despite unchanged pixels. Removing dimensions
from leaf hashing made the digest assertion fail ownexit1 for the reshaped raster.
Source restored byte-for-byte, SHA256
74eb0f623bc1704284424a0b9b267662a450ef88c4d7e44ef83bee184987530e;
all seven restored cases passed ownexit0. Finite900-second full gate is live under
session30468, log `/tmp/zpl-finishing-raster-full.log`. No full result claimed yet.

## Remaining integration and physical gates

Accepted original-document and workflow/ticket provenance, ordinary normalized
command bytes and output framing, qualified cut/file-boundary semantics, peel waits,
status/fault/isolation behavior and device lifetime coordination. Native mechanical
editing, M1 privileged identity/lifecycle, installed queues/dialog/defaults,
accessibility, USB and real output remain open. No printer/admin/merge/binary
publication. Frozen Part B unchanged.

## First full gate and complete barcode-budget audit

Initial full gate failed ownexit1:89Python/270Core debug/release and321Mac debug
passed; release321 had one saved-barcode reopening timedOut failure. No packaging
or signature pass is claimed for that gate. The four real-barcode correctness
scenarios now share the explicitly named production60s budget, with an audit test
enumerating all2/1/3/4 deadline call sites. Dedicated0.05/0.1s deadline tests are
unchanged. See M2-BARCODE-CORRECTNESS-BUDGET-2026-09-17.md; exact timing cause remains
unestablished. Focused suites and subsequent finite900s full gate run session9657,
log `/tmp/zpl-finishing-raster-full-budget-audit.log`. Source remains local/unpushed.


## Terminal audited full gate

Full finite900s gate completed ownexit0:89Python/270Core/322Mac debug/release, independent oracle/finite inert ABI and pipeline checks, ARM/minimum26 metadata, nested local ad-hoc signatures and packaged-worker PBM/ZPL equality. Artifact artifacts/setup-app.JX0Qc6. No printer accessed; no scheduler/GUI/installation/physical acceptance inferred. Session9657 is terminal; no restart required.

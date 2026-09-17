# Immutable finishing declarations — 2026-09-17

Partial M3-AC02/03/11 implementation, not mechanical acceptance.

Printer profile8 adds a required nullable `finishingConfiguration` field. Older
profile schemas reject it and retain exact canonical bytes. Profile8 retains all
profile7 thermal/geometry/offset fields. Generic immutable references allow8;
ordinary queues/tickets remain bounded to profile7 and reject non-tear controls.
No stock declaration or stored mode automatically enables device delivery.

The configuration stores enabled modes, separately evidenced mode facts, installed
accessory declarations, exact-media stock suitability, and independently qualified
cut-schedule facts and batch bounds. Configuration media must equal profile media.
Cut/peel/rewind facts must match the profile's model facts when supplied. Cutter
and peeler observations must agree with installation-reported profile inventory;
unknown inventory cannot become a positive installation observation. Enabled modes
must satisfy their own model/accessory/stock gates. Batch support requires evidenced
finite bounds; unsupported/unknown batch declarations cannot carry an invented limit.

The bounded canonical codec has fixed keys at every nesting level. Enabled names
are sorted, unique and limited to the four typed modes. Booleans require actual
JSON booleans, not numeric/string values. Missing versus explicit unknown facts
are preserved, as are unknown geometry and immutable loaded-media declarations.
Model source IDs and observation evidence use the existing bounded validation.
Utility revision copying retains the new configuration rather than dropping it;
native mechanical editing and ordinary profile8 admission remain separate work.

## Automated validation

All269 Core tests passed ownexit0, including three new persistence cases covering
canonical/null/legacy round trips, independent media/model/installation/stock/batch
contradictions, fixed keys, required version fields and strict boolean/set decoding.
Existing future-version tests now use9, keeping their unsupported-version assertion.
A native private-store cold-readback/conflicting-policy test is running before a
finite900-second full CI-equivalent gate. No broad result is claimed until terminal.
No printer/admin/merge/binary publication. Frozen Part B is unchanged.

## Remaining work

Ordinary finishing defaults and schedule precedence in versioned queue/ticket
binding, original-PDF preparation and normalization; qualified wire/file boundaries
and delayed-cut semantics; peel removal waits, mechanical faults and physical state
isolation. Native profile8 editing and queue management remain incomplete. M1
privileged identity/lifecycle, GUI/accessibility, USB and physical gates are open.
Installation declarations are supplied facts, not authenticated sensor evidence.

## Pre-publication boundary review

Queue/ticket role checks remain bounded to profile7. Direct control resolution
currently accepts a profile8 snapshot, while ordinary thermal command normalization
is implemented only for profile7. Storage-only profile8 must therefore explicitly
reject direct resolution and both ordinary encoding entry paths before publication.
Add the shared unsupported-version constraint and regression coverage for those
paths after the current full-gate process reaches terminal state. This is an
unpublished incomplete integration boundary, not a claim that profile8 is ready.

## Admission-boundary regression and first full result

The initial finite full gate failed ownexit1:89 Python/269 Core debug/release
passed, but native debug314 had one existing barcode-child timedOut failure.
No Mac release/signature/packaged result is claimed for that run. Its cause is
unestablished; production/test worker deadlines and assertions were not changed.

A new regression using a qualified direct-thermal profile7 copied into storage-only
profile8 failed ownexit1 on four independent calls before the admission guard:
resolveControls, direct control encoding, bitmap encoding, and profile preparation.
The shared OrdinaryPrinterProfileAdmission version constraint now rejects profile8
before resolving or encoding ordinary output. Profile7 remains successful. All270
Core passed ownexit0 afterward, including strict numeric/string/null rejection at
both installed-accessory and stock-suitability boolean paths. Native private-store
cold-readback/conflicting-policy test had passed ownexit0 before the first full gate.
A new finite900-second full gate is live under session82592; no terminal result yet.
Source remains local/unpushed until terminal green and disclosure review.

## Terminal combined validation

Finite900-second `bash scripts/ci-swift.sh` passed ownexit0 with the explicit
correctness-budget restructure:89 Python/270 Core/314 Mac debug/release,132 original
and180 ASCII oracle round trips per mode, finite benchmark/inert ABI/pipeline
harnesses, ARM/minimum26 metadata, nested local ad-hoc signatures, unavailable
Developer-ID negative and packaged-worker PBM/ZPL equality. Local artifact
`artifacts/setup-app.FwiqW0`. Earlier failures remain recorded; their timing cause
is not established. Automated results do not establish installed/GUI/physical
acceptance or five-second barcode latency.

Deliberately removing the exact stock/profile media binding made its regression
fail ownexit1 (missing expected throw). Source restored byte-for-byte, SHA256
e79a2f518880d87c6e1076a80f51a7397553c6e3c80eeeae76cf5882b665f632;
all270 restored Core tests passed ownexit0. The four ordinary admission calls
also failed before the shared version guard was introduced.

# Qualified in-memory finishing output framing — 2026-09-17

Partial M3-AC03/11 software implementation, not physical finishing or adapter acceptance.
FinishingOutputQualification binds additional command/status/adapter declarations to
an exact complete immutable PrinterProfile as well as its model. It requires model-
documented mode, one-label quantity and correlated label-completion semantics.
RFID void-label behavior is not implemented: a documented non-RFID model fact is
required; unknown is not absence. Cut additionally requires separately documented
^MMD support, delayed-cut readiness and cut completion, plus reported adapter support
for complete separate files. Ordinary ^MMC support does not imply these. Unknown file
support differs from explicitly absent support; model-only file observations cannot
prove a running adapter. Peel requires documented label-taken semantics; prepeel
syntax is independently documented as supported (explicit N) or not applicable.

FinishingFramedOutput creates bounded in-memory steps from the actual sealed original-
source preparation and retained normalized controls. It checks profile/plan context
and ordered packed-input binding before encoding. Each already-expanded label has one
complete ^XA/normal/mode/graphic/^PQ1/^XZ format file followed by an explicit correlated
label-printed requirement. Tear-off uses ^MMT; rewind ^MMR. Peel uses ^MMP,N only with
prepeel syntax support, otherwise qualified ^MMP, then requires removal after every
label including the last. Cutting uses ^MMD; after each validated scheduled boundary,
steps require delayed-cut readiness, a separate ~JK-only file, then cut completion.
No ^MMC substitutes for batch/end intentions, and no cut trigger is appended to a
format. Format files and status requirements cannot be flattened into a raw-TCP job.
There is deliberately no concatenated whole-job byte property and no delivery adapter
accepts this candidate as device-write authority.

Encoded bytes share a1–64MiB total budget including separate cut triggers. Canonical
bounded graphic writing reuses the existing32,000-dot coordinate limit; source raster
caps are not a promise that every capped raster is encodable. Finite positive at-most60s
encoding deadline/cancellation are checked before preparation, between labels, in band
callbacks and before return. The validated10,000-label plan bounds step count to50,000.
No calibration/reset/persistent-save/firmware/destructive or accessory-enabling I/O occurs.

## Focused and regression evidence

Six Core and nine native focused cases passed ownexit0. Coverage includes all four modes,
complete snapshot/model mismatch, independent missing quantity/completion/delayed/readiness/
cut-done/file/label-taken/prepeel/RFID facts and evidence, invalid identifiers, unknown versus
false file support, unused mode-specific facts remaining irrelevant, both peel encodings,
actual original-source graphic equality, engine-expanded one-copy formats, seven-label
batch boundaries3/6/7, exact wait/file ordering, exact aggregate budget and one-byte overflow,
cancellation and exhausted deadline. Status steps are requirements, not observations.
Quantity2 and ordinary ^MMC fault substitutions independently failed ownexit1, restored
framer SHA25655e0490f3533320176462559803d3b6a0471fed129d8c2dd216a4459982839c5.
Omitting complete-profile binding failed ownexit1 on same-model changed revisions;
qualification byte-restored SHA256
60c7bc016c11d4f699b0cf61536260939a064c1e8a4b0504858d41c7f5bb1c17.
Six restored Core/nine restored native focused cases passed. The finite900s full gate
completed with its own exit0: 89 Python, 272 Core and 324 native tests in debug/release;
132 strict and 180 ASCII oracle round trips per mode; finite benchmark, inert ABI and
pipeline checks; ARM/minimum26 metadata, nested local ad-hoc signatures, unavailable
Developer-ID negative and packaged-worker PBM/ZPL equality all passed. Local artifact
artifacts/setup-app.P5wHzx was built; no printer was accessed. Independent oracle coverage of reused graphics does not
establish physical command/status/file-boundary semantics of this new framed candidate.

## Provenance and remaining gates

R45 cached official Zebra guide hash verified
b1f83b0822f176bb20b7cfe14a37ea33fb552c3d6bcf05da1b4c2704ad3aaa0c.
^MM printed305–306 specifies model-dependent modes/prepeel, removal waits and separate-file
~JK requirement; ^PQ printed324 specifies quantity. No third-party driver inspected/copied.
No manual PDF committed. Synthetic model facts do not qualify a physical printer.
Actual qualified file delivery and correlated bounded status provider; uncertain-delivery/
no-replay behavior and cross-process device ownership through completion/removal waits;
accepted queue/ticket/device/pitch binding and persistent qualification; adapter/lifecycle,
GUI/accessibility and approved matching-accessory physical tests remain open. Ordinary
schema8 paths stay gated. Frozen B unchanged; no printer/admin/merge/binary publication.

Full gate session6593 returned FULL_GATE_EXIT 0; log `/tmp/zpl-finishing-framed-full.log`.
Source hashes above remained unchanged through the full gate. Nearest independent
constraints are exact immutable-profile binding, already-expanded quantity ownership,
and separate delayed-cut file boundaries; the three fault checks exercise these in
combination with actual prepared original-source rasters or same-model profile revisions.
Manual source and tracked/new-file disclosure review passed. Previous published head
07ef3161fb53567cb22dffefaf534ba7005ac955 has exact hosted run35229621380 success;
that result does not cover this new slice.

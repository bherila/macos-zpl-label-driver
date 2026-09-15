# M2 — Geometry, imaging and ZPL engine

**Dependencies:** M0; use M1 input/transform findings for production adapter integration
**Goal:** Produce deterministic, bounded label output from original documents with an exact monochrome preview.

## Geometry and rendering

Implement the shared geometry contracts first: PDF boxes and origins, page rotation, supported UserUnit behavior, physical units, actual device resolution, printable bounds, uniform fit/actual-size policies and explicit source region. Clip selected content before it can enter another label. Apply rotation and dot rounding once. Non-finite, empty or out-of-bounds geometry must fail before allocation or device output.

Implement an unprivileged Quartz renderer in LabelMac. Render directly from the original PDF page into the final intended device geometry on an explicit white background. Handle transparency, vector paths, text, embedded raster images, rotated pages and multiple page sizes. Test PDF annotation/form-field appearance behavior: visible labels must not silently lose important annotations that a basic page-content API omits. Define flatten/reject support rather than assuming every PDF viewer renders identically. Encrypted, damaged and unsupported inputs produce distinct useful errors.

The first production input is PDF; add other documented image/raster inputs only with validated format metadata. Never sniff a document and reinterpret it as raw ZPL as a fallback. Low-resolution sources may be warned about; the engine cannot infer lost detail.

## Monochrome and preview

Provide separate text/barcode threshold and photographic-dither modes, with deterministic parameters in the job ticket. Make anti-aliasing/interpolation choices explicit and test them; there is no universal 'turn anti-aliasing off' rule. Mixed content requires a documented policy, not accidental global dithering.

The final preview is generated from the exact packed one-bit buffer used by the encoder. Test bit order, black/white convention, stride, byte padding and coordinate direction. Distinguish screen scaling of that bitmap from the underlying printer-dot image. Never show a higher-fidelity independent preview as if it were actual output.

## Encoding and preparation

Emit complete ZPL formats containing bounded graphic bands with correct offsets and decoded-byte counts. Use an independently implemented minimal test decoder/oracle and known expected vectors. First land plain ASCII hex; then add documented lossless compression with strict capability selection and bit-exact round-trip tests. Respect both public command limits and model-specific narrower bounds.

Prepare the complete bounded output before physical delivery by default. Rendering may use per-page temporary buffers/files; job limits must prevent unbounded RAM/disk growth. Introduce a worker deadline/cancellation design capable of interrupting stuck native rendering without escalating privilege. The CLI exposes conversion and preview only; printing remains explicit and separate.

## Proposed CLI (implement and document; not present in scaffold)

```sh
label-driver convert sample.pdf --job-ticket ticket.json --output sample.zpl --preview-dir previews
label-driver validate sample.pdf --job-ticket ticket.json
```

Define stable exit/error codes and a machine-readable result option. Validate output paths as normal user-owned CLI files; never permit arbitrary paths from CUPS job options. Production filter stdout must contain only its declared output format.

## Quality and performance

Separate byte-exact bitmap/encoder tests from Quartz rendering regressions. Analytic shapes can be exact; font/text/image baselines may require OS-specific reviewed tolerances and structural assertions. Do not regenerate every golden when a test fails. Profile release builds on a reference Mac. Set regression budgets after measurement; shared hosted-runner timing is informational, not a precise performance SLA.

## Reference geometry regression

Use [GC420d reference](../../hardware/GC420D.md): documented 8 dots/mm (0.125 mm pitch), not exact integer 203 DPI. For nominal 4×6 face and nearest-positive-half-away-from-zero rounding, expect 813×1219 dots, 102 bytes/row, 124338 bytes and 3 white final-byte bits. Keep the old 812×1218 example only as a nominal-integer-DPI synthetic case. Test round-once physical transforms, 832-dot head limit versus stock extent, and no guessed liner/gap/printable region.

Prototype a bounded 32,768 decoded-byte band cap as a project policy, not a certified device limit; at 102 bytes/row the planned row split is 321/321/321/256 within one label. The field limit still comes from the command specification. Independent decoding must reassemble exactly; no extra feeds or labels at band seams. Compression stays off for first hardware proof until firmware behavior is evidenced.

## Related documents

Read [acceptance](ACCEPTANCE.md), [instructions](INSTRUCTIONS.md) and [validation](VALIDATION.md). Shared [contracts](../../CONTRACTS.md), [sprint baseline](../../SPRINT-BASELINE.md), [local signing](../../LOCAL-SIGNING.md), [release scopes](../../RELEASE-SCOPES.md) and [validation policy](../../VALIDATION-PLAN.md) apply.

## Primary references

[R07](../../REFERENCES.md#r07), [R08](../../REFERENCES.md#r08), [R09](../../REFERENCES.md#r09), [R10](../../REFERENCES.md#r10), [R26](../../REFERENCES.md#r26). Documentation supports APIs/model facts, not unperformed runtime or physical tests.

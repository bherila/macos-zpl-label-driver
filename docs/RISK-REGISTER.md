# Risk register

| Risk | Earliest gate | Required mitigation / decision |
|---|---|---|
| Modern macOS does not expose all PPD controls | M1 | Actual system-dialog proof; evaluate adapter alternatives without silently dropping requirements |
| Browser path rasterizes/clips upstream | M1 | Separate input media, capture real data, qualify fidelity; no fake reconstruction claim |
| Spooler cannot read profiles/load Swift runtime | M1 | Installed scheduler/permission test; validated non-home config and native dependencies |
| Held jobs pick up changed profiles | M1/M4 | Immutable revision binding and preservation tests |
| Lock ends before backend/device work | M1/M3 | Actual downstream lifetime owner and two-process tests |
| PDF annotations/forms differ from visible source | M2 | Explicit flatten/render/reject contract and fixtures |
| Global threshold/dither damages barcodes | M2 | Content policy, exact preview, source/output decode and physical scans |
| Excessive memory or malformed PDF stalls printing | M2 | Checked bounds, private staging quotas, isolated worker deadlines |
| Model/firmware/installed accessory mismatch | M3 | Capability provenance, unknown states, physical qualification |
| Scheduler replays an uncertain job | M3 | Verified backend exits/retry policy, explicit uncertainty and no blind replay |
| Carrier changes sheet layout | M4 | Versioned structural matching, negative cases and hold/review behavior |
| Multiple-region extraction drops instructions/customs pages | M4 | Complete page accounting and explicit routing/skip policy |
| Privileged helper accepts arbitrary paths/commands | M5 | Allowlisted protocol, signature/client verification, anti-substitution tests |
| Drag-and-run UX needs more approval steps than expected | M5 | Record real OS flow; maintain native guided installation without promising one password |
| Exact minimum/current Tahoe patch differs from hosted image | M0/M6 | Target 26.0; record observed 26.x runtime and guard later APIs; no older-macOS backport work |
| No-account installer/helper admission or trust design fails | M1/M5 | Prove local ad-hoc path early; secure explicit authorization; no Team-ID assumptions or weakened authentication |
| Broad printer-support claims outrun evidence | M6 | Per-configuration support matrix and release traceability |
| Hosted CI evolves or incurs unexpected costs | M0/M6 | Standard labels, version evidence, reviewed updates, short artifacts, no paid capacity |

Do not close a risk by rewording an unimplemented requirement. Record evidence, a scoped restriction, or a maintainer-approved design decision.

Additional reference risks: nominal 203-DPI arithmetic disagrees with documented 8-dot/mm geometry; pre-cut stock is mistaken for a measured gap; 4×6 face is mistaken for liner/pitch/head extent; GC420t ribbon settings leak into GC420d; unrelated original queue bypasses local coordination; current-OS hosted tests are called clean-host installation evidence. Apply the reference hardware/first-run oracles and scoped evidence policy.

# In-worker memory telemetry

Optional bounded render-worker RSS telemetry now travels through private result validation, CLI JSON and offline benchmark reports without an intermediate process. Unavailable remains nil/null; invalid0/negative/above1TiB values reject before returned payload.41 focused native tests passed debug/release; validation omission fault produced3 expected failures;106Python tests passed. Actual six-run offline measurement succeeded; CLI/worker peaks separate, not simultaneous aggregate memory. Native GUI/scheduler/install/hardware gates unchanged.

Darwin measurement uses getrusage(RUSAGE_SELF) inside the original supervised
worker, after preparing/writing output and before serializing final metadata.
Apple's XNU manual documents ru_maxrss in bytes:
https://github.com/apple/darwin-xnu/blob/main/bsd/man/man2/getrusage.2
This avoids the rejected time-wrapper parent substitution. Measurement failure
or an unrepresentable metric reports unavailable; it never substitutes zero.
The1TiB protocol scalar cap is validation, not an allocation allowance.

Nearest independent constraint: optional diagnostic telemetry must not bypass
artifact admission or change ownership/supervision. Three malicious result
fixtures supply0,-1 and cap+1 along with otherwise admissible artifacts. Removing
the telemetry guard yielded three expected failures; exact restoration passed.
Legacy result JSON without the field decodes as unknown. Python rejects bool,
string, fractional, zero, negative and above-cap telemetry too.

The first release run selected a stale debug worker and failed its positive
telemetry assertion. Both hard-coded cross-configuration helpers (render-worker
and Quartz CLI tests) now filter candidates to their actual compile configuration.
An initial malformed-metadata fixture attempted to overwrite a read-only
executable; unique fixture files corrected it. No product safeguard was relaxed.
Both corrected configurations passed41 tests. Benchmark default path now uses
SwiftPM's release directory rather than a missing architecture-specific path.

A successful measurement captured separate CLI and worker peaks through output
preparation. It excludes any later metadata/startup-tail peak and does not claim
simultaneous process-tree memory, installed throughput or physical delivery.
No A/I/H/R acceptance was refreshed, no printer queried, and no artifact published.
The preceding integrated baseline remains a preceding-source result; focused
checks here are not a new full suite/signature/installation claim.

## Clean committed-source measurement

Raw evidence: M2-IN-WORKER-MEMORY-BASELINE-2026-09-17.json. The default-path harness completed exit0 on clean committed source, one first and five repeat invocations. It binds exact source, CLI and worker hashes and synthetic input hashes. Maximum repeat worker RSS: 18087936 bytes; maximum repeat CLI RSS: 18202624 bytes; repeat p95: 128.568ms. These remain separate per-process observations, not aggregate/physical performance.

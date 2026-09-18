# Read-only finite M1 job-attribute verifier

Additional implementation/automated preparation for M1-AC01/04/08/09/11/13.
No installed-scheduler criterion is closed. Held-job validation, administrator
installation, filter invocation/log routing and all physical output are NOT RUN.

The developer-only Python helper reuses `/usr/bin/ipptool` and `lpstat`, not a
new IPP implementation. It offers only `--queue-absent` or `--held-job NUMBER`.
No install/submit/release/cancel/remove/printer operation exists. A numeric job
selector is a canonical positive CUPS signed-32-bit integer. No arbitrary endpoint,
instruction file, operation, output path or document can be supplied.

Every client runs in a fixed empty controlled environment. CUPS_SERVER/IPP_PORT
presence is rejected before any client call. Discovery must return exactly one
absolute root-owned socket; URI-host percent escaping selects that observed
Unix socket for the native client. Ancestors are root-owned, non-world-writable;
group-writable system root/daemon namespaces (GID 0/1) are explicit. Initial live
validation rejected the observed root:daemon 775 `/private/var/run`; the corrected
rule models that existing system namespace without changing permissions. Unknown
group-writable/user-owned ancestors remain rejected. This is OS namespace trust,
not cryptographic server identity or privileged caller authorization. A root or
equivalently authorized system service changing the endpoint is outside that
claim; no new installer trust assumption is established.

Program-literal read-only IPP requests are written into a fresh private scratch
directory, never loaded from untrusted external instruction files. Commands have
one cumulative 20-second deadline, five-second native timeout and 65536-byte
captured-output cap. The parent drains nonblocking output and kills/reaps only
its owned command on failure/timeout, with at most three seconds of termination
confirmation grace. Unconfirmed termination is a distinct failure, never an
unbounded process-context wait or a successful cleanup claim. Child diagnostics/metadata are not forwarded
or retained. CLI output contains fixed scope/result/error codes, never actual job
IDs, hostnames, paths, titles, users, raw unknown options or documents.

Held mode first requires exact `file:///dev/null` queue URI. Native predicates
then require stopped/rejecting/unshared state; every outstanding fixed-queue job
must be the expected held ID; its destination, held state, one document, one
copy, supplied PDF format and indefinite hold must match. Missing fields/errors
reject; later tests skip after the first failure without turning it into success.
These are cooperative point-in-time checks, not a lease/atomic snapshot. A
successful check cannot authorize broad cleanup or automatic release/replay.

## Executed evidence

Before affected work the accelerator passed exit 0, including 132 independent
round trips, 15 backend/12 filter ABI cases and one inert pipeline. Existing
bitmap, encoder, order planner, source PDFs and independent decoder are unchanged.

All 15 final focused Python tests passed on the local Mac. Fourteen are portable
validation/resource/privacy cases. One required native-Mac case uses the real
ipptool against one owned Unix-socket HTTP 503 fixture; it observes the exact
POST resource and expected failed client status. This is a finite test-only
HTTP sink, not an IPP server/decoder or product integration replacement. It
proves native percent-escaped socket-host routing without CUPS/hardware access.
Linux explicitly skips that native-only case; missing ipptool on Mac fails.

The live read-only `--queue-absent` mode passed against the observed local
scheduler's absent experimental queue. It requests only printer-name and requires
client-error-not-found. No actual/invented job was queried. Observed host:
macOS 26.6.2 / 25G83 ARM, installed CUPS ipptool v2.3.4, Swift 6.3.3,
Xcode 26.6 / SDK 26.5. No 26.0-runtime coverage is inferred.

The first full gate at `66ab5db` passed exit 0: 81 Python/178 Core/258 Mac
debug/release and all accelerator/inert/signature/packaged checks; it did not
exercise the subsequently identified termination-confirmation fault. A new thrown
fault regression then failed with the old process-context cleanup, reproducing
its fallback behavior without leaving a real process alive. The correction uses
explicit bounded cleanup and closed parent pipes; all 15 focused tests and the
live absent-queue query passed again. The corrected full gate at `eb46f13`
passed exit 0: 82 Python/178 Core/258 Mac debug/release, both 132-round-trip
accelerator runs, 15 backend/12 filter ABI cases per mode, one inert pipeline
per mode, local ad-hoc ARM/minimum-26 signatures and packaged-worker exact
PBM/ZPL equality. The new regression is included in both Python runs.
This mocked termination failure is not a kernel/process-kill or power-loss test.

PR #73 hosted run 35115902706 passed at exact published `03992fd`; fetched
logs verify 82 Python/178 Core/258 Mac debug/release, both independent accelerator
runs, inert ABI/pipeline checks, local signatures and packaged-worker PBM/ZPL
equality. First correctness review completed clean at base `fa6c247` /
head `03992fd`: reviewer thumbs-up, no inline findings or threads. No merge.
Publication relative to corrected tested source changed evidence/manifest only.

Parent PR #72 exact `fa6c247` hosted 35112614847 passed: logs verify 178 Core,
258 Mac debug/release, 12 filter cases in both modes, local signatures and
packaged-worker PBM/ZPL equality. First review is clean at unchanged base
`889472c` / head `fa6c247`, with no findings/threads; no merge. Its private
warning-filter candidate passes copied-byte checks but OS administrator
authorization is unavailable noninteractively. No --apply or queue/job followed.

Next: actual finite held-job readback only inside
the approved one-job administrator session. Do not infer document fidelity,
profile snapshot ownership, production worker access, USB, scan or release
acceptance from this read-only helper. See R40 and the finite admission procedure.

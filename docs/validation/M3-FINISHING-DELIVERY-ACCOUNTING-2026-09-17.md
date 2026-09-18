# Finishing file/status delivery accounting — 2026-09-17

Partial software work toward M3-AC09; no integration or hardware acceptance.
FinishingDeliveryTracker retains the complete immutable framed candidate and
requires exact ordered step index and file payload before recording a send attempt.
Cumulative per-file accepted counts must be monotonic and bounded. Invalid accounting
makes the result uncertain. File completion advances only to its following status
requirement; transport acceptance never satisfies printing, cut completion or removal.
Unknown and unsatisfied status remain waiting. Only an explicitly confirmed observation
of the exact current step advances. The future provider must establish actual correlation;
this caller-supplied enum is not a hardware receipt or device-write authorization.
Any timeout/cancellation/failure after an attempted file, including zero known accepted
bytes and final peel removal, is uncertain and cannot automatically replay. Only an
explicit pre-attempt failure permits automatic retry; pre-attempt cancellation does not.
Terminal results cannot restart or change. No transport, query or device I/O was added.

Nearest independent constraints: a send attempt is not proof of zero delivery, and a
complete file is not proof of physical completion. Existing actual original-source
all-mode framing tests now exercise these together with ordered file/status/cut/removal
steps, wrong indexes/payloads, partial delivery, invalid/decreasing counts, missing status,
final completion, safe pre-attempt failure and cancellation. Nine focused native cases
passed ownexit0. Replacing attempted-file accounting with positive-byte accounting failed
with eight assertions (ownexit1); byte-restored nine cases passed ownexit0.
Restored tracker SHA256 ca0ffbed996022a3f45e55dcc2353c6730ae6a69c09bec89ee4930ce08210044.
Logs: /tmp/zpl-finishing-delivery-focused.log,
/tmp/zpl-finishing-delivery-attempt-fault.log,
/tmp/zpl-finishing-delivery-restored.log. Full finite900s session75954 completed FULL_GATE_EXIT 0:89 Python/272 Core/324 native
debug/release tests,132 strict/180 ASCII oracle round trips per mode, finite benchmark,
inert ABI/pipeline, ARM/minimum26 metadata, nested local ad-hoc signatures, unavailable
Developer-ID negative and packaged-worker PBM/ZPL equality passed. Artifact
artifacts/setup-app.8BT8lP. Log /tmp/zpl-finishing-delivery-full.log. No printer accessed.
Manual source review and tracked/new-file disclosure scan passed with zero markers;
restored tracker hash remained unchanged. Per-file cumulative increments sum to the
sealed candidate total, bounded to64MiB, and the sealed step array bounds indexes.

Remaining: persistence/restart recovery, accepted ticket/queue/device and pitch binding,
actual qualified file delivery/status correlation and bounded waits, shared cross-process
lease lifetime, scheduler retry policy and matching-accessory physical behavior. Ordinary
schema8 admission stays gated. Frozen Part B is unchanged. No administrator, physical,
merge or binary publication action occurred.

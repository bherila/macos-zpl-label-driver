# Direct null-output filter regression

Partial automated preparation for M1-AC01/09/11 only. Installed scheduler,
administrator admission, full-document fidelity and physical output are NOT RUN.

The frozen warning filter failed a direct synthetic ABI invocation with stdout
opened as `/dev/null` on the native Tahoe ARM host. The prior pipe-to-discard
success did not exercise this descriptor. Public CUPS v2.4.12 `scheduler/job.c`
selects negative final output fd for the null file URI; `scheduler/process.c`
opens that output directly as `/dev/null` (R42). This independent upstream source
does not establish the installed Apple scheduler's exact implementation.

The supplied filter harness adds both named-file and stdin direct-null cases,
with hard 15-second subprocess limits, exact successful schema-2 metadata,
byte counts, private-marker exclusion and false physical-output status. The
new named-file case failed on the old binary with the safe generic output error.
The offline accelerator before edits passed exit 0, including 132 independent
round trips, 15 backend ABI, 12 filter cases and one inert pipeline.

The correction compares stdout's `fstat` identity with `lstat` of the existing
root-owned character node `/dev/null`: device, inode and special-device identity
must all match; both descriptors' metadata must be character-device/root-owned.
Only that null sink skips poll, which reports POLLNVAL on this native host.
All writes retain nonblocking flags, short-write/error handling and the cumulative
deadline. Ordinary pipes retain poll/backpressure handling. No other character
device or arbitrary POLLNVAL gets a fallback; no device is opened by the filter.
Existing SIGTERM, broken-pipe, delayed-consumer and ten-second stalled-consumer
regressions remain mandatory. The bitmap, writer, planner and oracle are unchanged.

The focused build and all 14 filter cases passed exit 0, including both direct
null input modes and the retained pipe/cancellation cases. Complete local/hosted
gates are pending at this implementation checkpoint. The previous private frozen binary is not approved
for applying the experiment: it lacks this correction. After successful gates
and review, freeze and validate the changed executable's new signature/hash.
Do not silently substitute bytes into an older approved snapshot. The finite
one-held-PDF/one-copy/one-release/60-second observation and immediate owned-removal
procedure remains unchanged, with zero physical labels or printer commands.

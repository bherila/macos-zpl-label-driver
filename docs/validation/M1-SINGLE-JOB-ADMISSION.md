# M1 first administrator experiment: one held synthetic PDF

**NOT RUN.** This procedure is for the approved discard experiment only, not
production printing. Budget: one queue transaction, one single-page synthetic
PDF job, one release, a 60-second observation deadline, and immediate validated
removal. Zero physical labels or device commands. Do not retry failed jobs or
expand into a browser matrix during this session.

## Before administrator authorization

Freeze the exact tested commit, script hash, locally ad-hoc-signed ARM filter
hash/signature/deployment metadata, and approved native PPD hash. Use only
`Fixtures/generated/native-vector.pdf`; verify its committed manifest hash and
single-page identity. Run the script's read-only scheduler, filter, and PPD
validation modes. Stop unless the scheduler is reachable and the experiment
queue/root are absent. Record OS/build and toolchain.

Also record the configured logging level without changing it. The discard-only
filter's schema-2 `WARNING: LABEL_CAPTURE_FILTER` report explains that no physical
printing occurred. CUPS documents that WARNING is logged at warning level, whereas
INFO is error-log-visible only at debug2 (R39). An older INFO-only frozen filter
cannot establish this logging prerequisite. Re-freeze the reviewed new binary;
do not silently replace bytes under an older approval/checkpoint.

Keep a private local before/after record of queue inventory and system/user
defaults. Do not publish printer identities, device URIs, serials, or a full
system/log dump. Do not inspect unrelated driver assets. All queue/job commands
must use the same verified local Unix-socket endpoint, explicit `-h`, and a
controlled client environment with remote overrides absent, including privileged
operations. A failed query is not absence.

## Stage, submit, observe, remove

1. An interactive OS administrator runs the reviewed script's `--apply` with
   the frozen filter and native candidate. No password is collected by an
   agent/filter. Stop on any failure or residual report; retain recovery evidence.
2. Validate the final staged PPD strictly and inspect its planned chain using
   `cupsfilter --list-filters`, the final PPD, printer-format destination, and
   each source type separately: `application/pdf` and `application/vnd.cups-pdf`.
   This lists filters without executing them. Both must select the exact staged
   filter with no unexpected executable. Record diagnostics; do not loosen
   validation or global security. Read back the exact `file:///dev/null` URI,
   unshared status, disabled/rejecting state, and unchanged defaults.
3. Confirm no experiment jobs exist. Briefly accept jobs while leaving the
   queue disabled. Submit exactly one held job with explicit destination,
   `-H hold`, one copy, PDF document format, `PageSize=4x6.Fullbleed`,
   `ProbeSpeed=3`, `ProbeDarkness=15`, `ProbeWorkflow=Native`, and
   `ProbeRotation=90`. These are inert observation tokens, not physical control
   commands. Never use a raw submission path. Immediately reject new jobs again.
4. Validate the returned job identifier against scheduler readback: correct
   destination, held state, one document, and expected attributes. If another
   job appeared, stop; do not cancel an unrelated job or claim exclusive use.
   Preserve the experiment and report the conflict for administrator resolution.
   The read-only developer helper `python3 scripts/check_m1_ipp_readback.py
   --held-job NUMBER` performs fixed-queue URI, stopped/rejecting/unshared,
   outstanding-job and required held-PDF attribute checks through the explicitly
   selected socket. `NUMBER` is only the returned positive CUPS numeric ID, not
   an invented ID or a request from an unrelated queue. This helper never submits,
   releases or cancels work. Its checks are point-in-time observations, not an
   atomic scheduler transaction or authority to mutate a changed destination.
   Missing/unsupported attributes fail closed. The actual held-job mode remains
   NOT RUN until the approved administrator experiment; see R40 and
   [readback preparation](M1-READONLY-IPP-READBACK-2026-09-16.md).
5. Enable processing only after verification, then resume only that held job
   (`lp -i JOB_ID -H resume`, not restart). Observe for at most 60 seconds.
   Require scheduler-correlated `WARNING: LABEL_CAPTURE_FILTER` schema-2 metadata
   for this job, with matching positive numeric `jobID` and the fixed discard-only
   `auditReason`. The scheduler's own job context must independently agree;
   caller-provided JSON or a direct executable run is not scheduler evidence.
   Log formatting may represent warning severity separately rather than preserve
   the literal stderr `WARNING:` prefix; match the marker, complete schema and
   scheduler job context, not only a textual severity wrapper.
   Require:
   expected file/stdin mode, PDF input MIME, nonzero bounded byte count, copies
   argument, all four selected option values, and final MIME
   `application/vnd.labelprobe`. Require finite discard completion too. Completion
   alone, without this invocation evidence, is inconclusive. Do not enable global
   verbose/payload logging to compensate for missing metadata.
   Read only a finite window containing the exact marker for the owned job from
   the observed error-log destination. Do not assume a filesystem log exists or
   infer absence from a failed query. On the recorded host no traditional
   `/var/log/cups/error_log` existed and a 15-second-limited macOS unified-log
   query restricted to process `cupsd` and marker `LABEL_CAPTURE_FILTER` completed
   with no events before any job. That proves query availability only, not the
   runtime warning route. If neither the actual error-log sink nor the bounded
   marker-only unified-log query exposes the correlated report, record the
   admission result as inconclusive and stop; do not loosen settings or retry.
6. Reject further jobs immediately. If needed, cancel only the recorded own job
   and verify it drained. Run explicit script `--remove`; queue-first validated
   recovery must confirm absence before deleting the filter/intent/root.
   Compare baseline/defaults and unrelated queues. Report residual artifacts,
   uncertain job status, or query failure explicitly; never broaden cleanup,
   purge scheduler history/logs, or delete another queue.

The local `lp` and `cupsfilter` manuals were inspected when preparing this
procedure: hold/resume applies to a specific job; `--list-filters` does not run
filters. Exact host behavior still requires the administrator-session evidence.

## What this can establish

Only narrow real-scheduler filter admission, selected option propagation,
discard completion, and observed reversible installation. It does not close
all of M1-AC01/04/11/13, prove original PDF/vector fidelity, test system-dialog
visibility, establish held-profile revision binding, select a production worker
identity/IPC model, qualify restart admission, or validate USB/physical output.
Record those separately. The PPD remains an experimental candidate.

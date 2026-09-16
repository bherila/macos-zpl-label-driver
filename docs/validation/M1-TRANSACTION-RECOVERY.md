# M1 discard transaction recovery

This is a finite recovery guide for the one-off inert M1 experiment. It is not
a product uninstall contract and must not be used for unrelated queues or
files. The administrative `--apply` path remains **NOT RUN**. Reviewed source
and passing CI are prerequisites, not administrator-session or scheduler
acceptance; the finite experiment also requires interactive OS administrator
authorization and fresh read-only namespace/artifact checks.

## Normal preparation and removal

1. Run `scripts/m1-discard-file-sink.sh --scheduler-preflight`. It must report a
   reachable local Unix-domain scheduler endpoint and an absent experiment
   namespace. `CUPS_SERVER` and `IPP_PORT` overrides are rejected.
2. Validate the locally built filter and chosen supplied PPD with the two
   read-only validation modes.
3. After the separately authorized finite experiment, run
   `scripts/m1-discard-file-sink.sh --remove`. It authenticates once, then uses
   noninteractive privileged operations against the scheduler endpoint recorded
   in the protected intent file.
4. Treat any `RESIDUAL:` line as an incomplete removal. Preserve the root,
   filter, and intent record for diagnosis; do not broaden deletion.

Removal is queue-first. The script verifies the exact discard URI, removes only
the named queue, proves that queue is absent through a complete reachable-
scheduler query, verifies the filter hash, then removes the filter, intent file,
and empty root. A changed URI, failed query, failed deletion, expired
authorization, changed filter, or mismatched record stops this sequence.

Automatic rollback is narrower than explicit removal. It begins only after the
current invocation successfully reserves the protected root, requires that
invocation's random identifier in the intent record, and never removes a
present queue. The scheduler's queue operation is create-or-modify, not an
exclusive namespace acquisition: even a successful response and exact discard
URI readback cannot prove that no competing queue was modified. Any present
queue therefore retains the filter, intent, and root for explicit inspection
and separately requested record-validated recovery. Scheduler-query failure
also retains those artifacts. Automatic cleanup may proceed only when the
queue is confirmed absent and the remaining protected artifacts match the
current invocation's ownership evidence.

## Uncatchable interruption window

The protected intent is installed before the filter or queue. A power loss or
`SIGKILL` can still occur after atomic root-directory reservation and before the
intent file is installed. If the fixed root exists without `OWNERSHIP`, do not
let `--remove` infer ownership. An administrator must verify all of the
following before removing that one empty directory manually:

- the selected local scheduler is reachable and the named experiment queue is
  absent from its complete queue inventory;
- `/Library/Printers/LabelPrinterDriver-M1` is a real root/wheel directory with
  mode 0755;
- the directory is empty and contains no symbolic links or unexpected files.

If any condition differs, stop and preserve the state. Never delete another
queue, purge scheduler history/logs, remove a nonempty directory, or change
global CUPS security/configuration as recovery.

## Automated evidence

The unprivileged transaction harness injects lost responses after root
reservation, intent installation, filter installation, queue creation, disable,
and reject. It also covers a changed URI, scheduler-query failure, authorization
expiry, failed queue deletion, uncertain post-delete readback, altered filter,
partial state, pre-existing queue/root, and TERM. It also covers a losing root
reservation against both an empty and completed competing transaction, a queue
appearing at the late absence check, and an ambiguous queue-create response.
The later `9019eb6` regressions also cover a successful create-or-modify race
and termination during queue readback; automatic rollback performs no queue
deletion in either case.
These tests validate control flow only; they do not establish administrator-
session behavior or scheduler acceptance on Tahoe.

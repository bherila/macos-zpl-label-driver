# Current offline release performance measurement

Automated local measurement on 2026-09-17. The harness completed exit0 with
one first invocation and five subsequent independent invocations. No printer,
queue, administrator operation or GUI was used.

The raw report binds source checkpoint, executable and synthetic input hashes,
reference-machine model, OS/toolchain, output count, and every repeat sample.
The executable is the locally ad-hoc signed release copy from the current-source
signature run; signatures do not imply trusted publication or installed support.

- Environment: Apple Silicon MacBookPro18,3; macOS27.0 build26A428;
  Swift6.4; Xcode27.0 build27A266a.
- Output: 813×1219 dots, 991047 pixels, 248814 ZPL bytes, unchanged across runs.
- First invocation: 515.937 ms; reported maximum resident bytes17891328.
- Repeat median:129.968 ms; nearest-rank p95:138.331 ms (five samples).
- Maximum repeat reported resident bytes:18186240.
- Throughput at repeat p95:7164320 pixels/s and1798687 prepared bytes/s.

The first invocation exceeded500ms; repeat p95 was below500ms. The first
invocation is not a cache-purged boot/startup measurement. Five samples provide
a finite refresh, not a statistically strong tail-latency guarantee.

Memory is the maximum RSS reported by macOS `/usr/bin/time -l` for the CLI
command. No separate worker/whole-process-tree peak instrument was collected;
this report does not claim aggregate peak memory below256MiB. Output remains
the offline graphics envelope, not production state-normalized delivery.
M2-AC12 is not newly accepted or backfilled by this report; runtime26, production
workflow throughput and physical delivery remain unmeasured here.

Procedure: `python3 scripts/benchmark_offline.py --runs 5` with an explicit
current signed CLI path, and exclusive output in a temporary directory.
The committed raw JSON is the authoritative measurement artifact.

## Harness deadline follow-on

2026-09-17 offline benchmark now bounds each conversion at120s and metadata probes at30s; timeout kills the owned process group, including children holding pipes after parent exit. Four focused tests and full105 Python tests passed exit0; removing group cleanup caused the expected child-survival assertion failure, exact restoration passed. Actual finite six-invocation current signed CLI benchmark passed exit0 with unchanged output. No aggregate memory, scheduler, GUI, printer or new acceptance evidence.

Nearest independent constraint: an exited benchmark wrapper may leave a child holding captured output pipes, so a finite timeout must terminate the owned process group rather than only the wrapper PID. The synthetic regression uses an exited parent plus a delayed child marker; no transport is opened. Cleanup never targets unrelated groups. Each conversion has an explicit120-second deadline and timeout cleanup waits are finite. This does not claim to control descendants that deliberately leave the group.

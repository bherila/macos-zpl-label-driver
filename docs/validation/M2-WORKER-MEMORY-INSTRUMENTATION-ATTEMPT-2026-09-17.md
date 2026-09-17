# Worker memory instrumentation attempt

Status: NOT MEASURED. A finite120-second local diagnostic attempt completed
exit65/PREPARATION_FAILED. Disposable private tools wrapped the exact signed
release render worker with `/usr/bin/time -l`, preserving argument bytes and
stdout. Synthetic offline input only; no printer or queue was accessed.

The wrapper introduces the time process as the worker's parent. Actual source
LabelRenderWorker/main.swift passes the recorded parentPID to
RenderWorkerSupervisor; its initializer requires getppid()==parentPID. Thus the
instrumented process tree violates the supervised worker contract. This is an
instrumentation incompatibility, not evidence that ordinary conversion fails.
The prior unwrapped finite benchmark and integrated baseline remain separately
recorded. The disposable tools were removed by the temporary-directory scope.

Do not rewrite the recorded parent PID, weaken supervision, bless a wrapper or
label this observation a memory pass. No worker memory observation was retained;
CLI RSS from the failed preparation is not successful processing memory.

The next independent implementation route is bounded scalar memory telemetry
collected inside the existing worker process, with explicit protocol validation,
redaction and tests. Keep peak worker memory distinct from simultaneous aggregate
process-tree memory and measured startup overhead. This requires no printer,
administrator or manual GUI evidence. No product source or acceptance ledger was
changed by this experiment. M2-AC12 remains unaccepted for this missing scope.

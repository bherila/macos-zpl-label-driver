# Worker lifetime and abandoned scratch recovery

PR #50 remediation for the independent worker-lifetime finding at `77874a3`.
This advances partial M2-AC09 and M4-AC06/09 automated evidence only.

The real render/analysis child starts a dedicated finite supervisor before native
document processing. It exits on parent loss or its remaining monotonic deadline
(at most 60 seconds), independently of the parent's event loop. Parent and child
hold shared locks on a canonical nonce-bound ownership record containing the
scratch directory's device/inode identity. The setup app performs bounded recovery
at startup. Recovery requires a proven absent parent, an exclusive marker lock,
exact directory identity, and a fully allowlisted private regular-file namespace.
Unknown, unmarked, replaced, locked, or ambiguous material is retained and reported.
PID reuse conservatively retains material. CLI users may invoke the explicit
recovery API; a terminated CLI does not itself run startup recovery.

Five focused native tests passed on 2026-09-16: dead-parent locked/unlocked
recovery; live-parent and unknown-artifact retention; replaced directory and FIFO
marker rejection; nonce/scan limits; and a subprocess fixture exercising an
independent deadline plus actual parent termination and subsequent recovery.
The fixture blocks its main thread; it does not reproduce a particular Quartz
hang. It uses the same supervisor and marker protocol as the real worker.

The full local `bash scripts/ci-swift.sh` gate passed: 67 Python tests,
166 LabelCore and 177 LabelMac tests in debug and release, 132 independent
round trips, 15 backend ABI cases, 10 filter ABI cases, one inert pipeline case,
ad-hoc executable/nested-worker signatures, and packaged-worker PBM/ZPL equality.
Second independent review and hosted exact-head CI remain pending. No GUI,
installed scheduler, privileged installation, transport, or physical acceptance
is established. Supervision requires OS scheduling; it is not a hard real-time
or power-loss guarantee. SIGKILL cannot run parent cleanup. Recovery is narrowly
owned temporary-data cleanup, not a spool/job retention implementation.

# M2 render-worker cancellation admission — 2026-09-16

The existing isolated offline renderer now checks already-requested cancellation
after bounded argument validation and before executable inspection or source
staging. It checks again immediately before launching the child. Cancellation
at that second check retains its distinct error and private scratch cleanup,
rather than being mapped to worker-unavailable.

A regression passes an already-cancelled bounded request with an unavailable
worker path and requires `cancelled`, proving executable availability is not
consulted for that request. Existing live-child cancellation and timeout tests
remain passing. This is not atomic cancellation/send arbitration: cancellation
arriving after the final check is handled by the existing owned-child polling
and termination path. It provides no transport authorization or scheduler claim.

Local `bash scripts/ci-swift.sh` completed with exit 0 on the existing Tahoe ARM
host. Its log confirms repository preflight, 67 Python tests, 165 LabelCore and
153 LabelMac tests in debug/release, 132 independent round trips, 15 backend
and 10 filter ABI cases, one inert pipeline case, and local ad-hoc command/app
signature verification. The focused worker suite passed all eight tests.

This adds automated M2-AC09 cancellation evidence only. The connected synthetic
extraction pipeline still renders in-process; integrating isolated region
rendering remains separate work. No queue, administrator operation, scheduler
job, device, or physical printer was used. Hosted exact-head validation remains
completed: automatic run [35071875026](https://github.com/bherila/macos-zpl-label-driver/actions/runs/35071875026)
passed exact `cf379e81c7f25a0c9440717eb35cee8d8a50242f`, with repository,
native macOS ARM, and required aggregate green. Inspected hosted logs confirm
the same 67/165/153 debug/release suites, independent oracle/ABI/inert checks,
and ad-hoc signatures. Independent code review completed cleanly at the same
head against base `42a4c80966f4135973a5fcb42a3f82368d4d36ae`, with a thumbs-up
and no inline findings. No repeat review is requested for a clean first pass.

# M3 isolated extraction preparation — 2026-09-16

Synthetic descriptor intake now requires a render-worker executable for new
preparation. It serializes each exact immutable plan item (source page, region,
expected source rectangle, rotation), output canvas, and ticket-bound monochrome
policy into the existing extraction-aware worker contract. No in-process
rasterization fallback remains in this pipeline.

The parent checks returned canvas dimensions, exact binary PBM header/count,
canonical packed padding, and equality of regenerated diagnostic ZPL. Only the
validated bitmap reaches the existing production control encoder. Immutable
printer/default resolution, cumulative output budget, complete prepared
publication, ticket-derived lease, persisted send intent, and inert-only delivery
remain unchanged. The worker's diagnostic envelope is never sent as a prepared
production job.

Existing connected intake tests now run through the real child. New regressions
reject mismatched dimensions/header, truncated/extra bytes, nonwhite row-padding
bits, and unrelated ZPL. An unavailable worker leaves the exact accepted source
and lifecycle `accepted`, without prepared publication or send intent.
Debug/release intake tests select the corresponding built worker configuration.

Full local `bash scripts/ci-swift.sh` completed with exit 0: 67 Python tests,
166 Core and 158 Mac tests in debug/release, 132 independent round trips,
15 backend and 10 filter ABI cases, one inert pipeline case, and ad-hoc
command/app signatures passed. Ten focused bitmap/intake tests passed.
Automatic hosted run `35073499862` passed exact cumulative head
`2e592f984b10fa0cf6fc24a1b71850695ecfa733`: repository preflight, native macOS
ARM and `ci-required` succeeded. Independent review completed cleanly at code
commit `38cef69486b9bdb8c4ca0102717e812a2b76b9f8` with a completed summary,
thumbs-up and no inline findings. The later head changes dependency evidence
only. The prior run was cancelled by that push, not a test failure.

This advances automated M2-AC09 and M3-AC12 only. The 60-second bound covers
each render child, not the entire job. PDF page/structural layout analysis still
runs in-process before acceptance and during retry validation; isolating it is
unfinished. Source staging repeats per label and is not optimized. No real
scheduler, installer identity/IPC, USB, device, or physical printer was used.

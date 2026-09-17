# Current worker-admission integrated native baseline

Clean evaluated local unpublished source: `4ddffeb40e1866629972f131df1048c26cac75e3`. The finite 900-second caffeinate-owned process-group wrapper ran `bash scripts/ci-swift.sh`; command's own exit 0. Timeout cleanup was not needed. Worktree was clean before and after execution. No ledger acceptance was refreshed.

Environment: macOS 27.0 build 26A428, ARM64, Xcode 27.0 build 27A266a, SDK 27.0, Apple Swift 6.4 (6.4.0.34.1). Build deployment target and packaged minimum-version metadata are 26.0; this run does not qualify a retail macOS 26 host.

| Validation | Executed result |
|---|---|
| Repository/Python | Preflight passed; 106 unit tests per accelerator mode, zero failures |
| Core | 301 XCTest tests debug and release, zero failures |
| Native | 370 XCTest tests debug (136.156 s) and release (96.333 s), zero failures |
| Independent oracles, each mode | 132 analytic/PBM/ZPL round-trips; 180 compression round-trips; 12 finite CLI benchmark cases |
| Inert adapters, each mode | 15 CUPS ABI cases; 14 filter ABI cases; one filter-to-discard pipeline |
| Local products | Release products/diagnostics, ARM inspection and minimum-26 metadata passed |
| Signing/package | Local ad-hoc signatures including nested worker verified; unavailable Developer-ID mode failed without silent fallback; packaged worker synthetic PBM/ZPL matched release worker |

Local app artifact: `artifacts/setup-app.GeEvs8/Label Printer Driver Setup.app`. This is a development artifact, not a published preview or replacement for the frozen Part B candidate. Source code, compiled/signature checks, GUI, scheduler, installation and physical printer results remain separate evidence levels. Logs: /tmp/zpl-worker-admission-full.log and /tmp/zpl-worker-admission-full-source.txt.

The baseline includes current control metadata, bare-host delimiter admission and all five worker fractional-integer admission routes. Tests use synthetic fixtures, inert workers/discard sinks and loopback peers. No physical printer I/O, privileged operation or product queue modification occurred. Manual GUI/accessibility, installed scheduler/admin, USB/unplug recovery, physical finishing/state isolation, clean retail minimum-runtime and release/distribution gates remain open. Hosted CI still does not cover this unpublished local source.

## Read-only private-record audit

AcceptedFinishingJobStore.parseRecord bounds the envelope/metadata/source and requires canonical manifest re-encoding to equal original metadata; load separately verifies archive/reference hashes. RenderWorkerScratch.readRecord uses bounded current-owner/single-link descriptor reads, directory/parent/token binding and canonical re-encoding equality. Numeric spellings changed by decoding cannot pass those equality checks; neither path was mechanically changed for the worker fractional-admission finding. These inspected guards are not a complete privacy acceptance assessment.

OfflineExtractionWorker.validate checks expected canvas dimensions, canonical packed PBM header/byte count and regenerated diagnostic ZPL equality. Ordinary render-result admission checks numeric fields and payload byte counts but does not itself apply that extraction oracle. Next independent implementation audit: determine whether every parent render route must share the bitmap/ZPL binding oracle, then add a failing real-boundary regression before any fix. M3-AC12 and the production privileged IPC/installer boundary remain open.

## Linux handoff

A local tracked-source archive at the evaluated checkpoint is ready: /tmp/zpl-current-linux-source.tar, SHA256 `c81f018a2f189513ec4cddf542baf902edf6bc60c6622869865c734b4d5717cd`. Its 521 archived files were compared against the exact git tree and matched. /tmp/zpl-current-linux-handoff.md specifies bounded portable validation, own exit-code/log reporting, synthetic-only fixes and no shared progress edits, printer access, privileged actions, push, merge or publication. No Linux worker was launched and no Linux result is claimed.

No merge or publication occurred. Next: parent output/artifact binding audit and reviewable source integration; preserve the manual candidate and all acceptance evidence boundaries.

# Offline lab failure privacy — 2026-09-17

Evaluated local unpublished source `4f8d38eb9c4c8087909dc36cb9d805e18bc48a86`. Advances normal diagnostic privacy; no whole M3-AC12 or release acceptance claim.

The lab formerly printed raw Foundation errors, including caller paths on output-directory creation failure. Four known lab failures now use fixed typed messages; unexpected errors use a fixed preparation-failure message. Exit2, empty failure stdout, useful usage/benchmark/existing-directory guidance and normal successful vector/benchmark output remain intact. This is a developer-only synthetic tool with no source-document or transport API.

Nearest independent constraint: diagnostic redaction must preserve failure signaling and no-clobber behavior. New check_lab_diagnostics invokes the real binary with a vector destination below a synthetic regular-file blocker and with the existing blocker itself. Each requires exit2, no stdout, nonempty path-free stderr, unchanged blocker bytes and no extra output. Each subprocess has a10-second timeout and uses owned temporary synthetic data. The accelerator calls it in both configurations; ci-swift already calls both accelerator modes. Independent bitmap/compression oracles are unchanged.

Before fix, the accelerator exited1 at the new blocked-destination privacy regression after existing source tests/oracles ran. Final debug and release accelerator each exited0:106Python,303Core,132strict vectors,180compression round trips,2real lab privacy cases,12benchmark CLI cases,15inert CUPS ABI,14inert filter ABI and1filter-to-discard case. Preflight/diff passed. Logs `/tmp/zpl-lab-privacy-before.log`, `/tmp/zpl-lab-privacy-debug.log`, `/tmp/zpl-lab-privacy-release.log`. Manual diff/disclosure reading: fixed vocabulary and synthetic fixture only.

Native LabelMac/full CI/app signing, Linux, GUI/VoiceOver, installed scheduler/admin/helper and physical-printer tests NOT RUN for this portable lab-only change. Older whole-source receipts remain historical. Frozen manual candidate/Linux archive unchanged. No profile/device commands, rendering/encoder changes, fixture/oracle changes, ledger refresh, printer I/O, queue/privilege operations, merge or publication. Next: current integrated native baseline and remaining privacy/source-integration audit; manual/production adapter/helper/USB gates remain open.

Implementation digests:

- `Packages/LabelCore/Sources/LabelCoreLab/main.swift`: `18a641b1fae348d00885f73b7a9f6a0051329d100e2abda9a3c25accd6efbc3c`
- `scripts/check_lab_diagnostics.py`: `e4c6bba824689fb748474141717f210107280366f3080e0edc6accae2a96df4b`
- `scripts/run-accelerator-checks.py`: `b909b76a3fa8d52a0d01cf8b10201dc86e3caef47030d6648e69c93d65faa915`

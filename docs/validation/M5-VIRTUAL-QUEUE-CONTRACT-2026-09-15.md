# M5 virtual-queue contract evidence — 2026-09-15

## Scope

Commit `d502d49` adds a portable, bounded contract for virtual queues. This is
implementation and automated-test evidence only. It did not create, change, or
remove a CUPS queue; install a component; contact a printer; or exercise an
administrator path.

Each queue binds immutable workflow and printer profile references by schema,
revision, and canonical SHA-256 digest. Multiple queues can target the same
opaque physical-device coordination digest without persisting a raw serial
number or device URI. Version 1 permits only the conservative reference
defaults: direct thermal, tear-off, and an optional speed already validated by
the bound printer profile. Darkness, tracking, media commands, paths, raw
commands, documents, unknown fields, oversized input, and noncanonical
identifiers fail closed.

The queue catalog rejects duplicate queue identities and groups queues by the
shared device coordination domain. This supplies a portable binding for the
existing cross-process device lease, but does not prove scheduler-level
serialization or lifecycle behavior.

## Validation performed

On Apple Silicon macOS 26.6.2 with Xcode 26.6:

- `bash scripts/ci-swift.sh` — PASS.
- Repository preflight and fixture integrity — PASS.
- Python tests — 56 passed.
- LabelCore debug and release — 136 passed in each configuration, including 6
  new virtual-queue tests.
- LabelMac debug and release — 74 passed in each configuration.
- Independent ZPL/PBM/analytic round trips — 132 passed.
- Inert CUPS backend ABI — 15 passed.
- Inert CUPS filter ABI — 10 passed.
- Inert filter-to-discard pipeline — 1 passed.
- Local ad-hoc command-line and setup-app signature checks — PASS; Developer-ID
  selection still fails closed when unavailable.

The six focused tests cover deterministic round-trip encoding, immutable
reference validation, conservative default validation, hostile unknown-field
rejection, shared coordination domains, duplicate identities, and input/output
size caps.

## Acceptance impact and remaining gates

This is partial automated support for M5-AC04, M5-AC05, and M5-AC07. Those rows
require real macOS integration and remain unchecked. Queue publication,
updating, restart behavior, held-job recovery, system-dialog option propagation,
preservation of unrelated printers/defaults, and cross-queue delivery
serialization remain untested. M1 scheduler admission, privileged installation,
Gatekeeper behavior, USB delivery, and physical output also remain unverified.

The next safe slice is a private immutable native store for these definitions
and exact-reference resolution. It must remain offline and must not mutate the
local scheduler until the authorized M1 administrative experiment is ready.

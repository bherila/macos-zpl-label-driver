# Immutable imaging-policy evidence — 2026-09-15

## Scope

Commit `8a7fef8` makes the one-bit conversion policy an immutable workflow and
accepted-job fact instead of an ambient renderer argument. Workflow schema 2
requires either a text/barcode threshold with an exact 0...255 cutoff or the
fixed photographic 4x4 ordered-dither policy. Schema-1 workflow bytes are not
silently assigned a policy and therefore fail closed on import.

The accepted ticket is likewise schema 2 and copies the exact workflow policy.
Decode re-resolves the immutable workflow reference and rejects any ticket
whose conversion differs. Complete prepared payloads carry the policy, and
publication rejects a policy that differs from the accepted ticket before
creating `prepared.zpl`. Verified prepared loads return the same ticket-bound
policy with the bytes, output order, printer snapshot, and resolved controls.

The native workflow editor no longer owns a separate conversion value. Preview
rendering uses the policy stored in the exact draft profile, so preview and a
future production preparer cannot diverge through separate defaults.

## Validation performed

On Apple Silicon macOS 26.6.2 with Xcode 26.6:

- Missing, unknown, out-of-range, and policy-inconsistent workflow/ticket
  encodings — rejected.
- Workflow schema 1 without an imaging policy — rejected rather than migrated
  with a guessed value.
- Threshold and photographic policies — canonical JSON round-trip passed.
- Ticket policy changed independently from its workflow — rejected.
- Prepared payload policy changed independently from its ticket — rejected
  before any prepared artifact was written.
- Native editor preview — passed using the profile-bound policy.
- `python3 scripts/run-accelerator-checks.py` — PASS.
- `bash scripts/ci-swift.sh` — PASS.
- Repository preflight and fixture integrity — PASS.
- Python tests — 56 passed.
- LabelCore debug and release — 164 passed in each configuration.
- LabelMac debug and release — 105 passed in each configuration.
- Independent ZPL/PBM/analytic round trips — 132 passed.
- Inert CUPS backend ABI — 15 passed.
- Inert CUPS filter ABI — 10 passed.
- Inert filter-to-discard pipeline — 1 passed.
- Local ad-hoc command-line and setup-app signature checks — PASS.

## Acceptance impact and remaining gates

This adds partial automated evidence for M2-AC05/M2-AC09, M3-AC02/M3-AC12,
M4-AC06/M4-AC09, and M5-AC07/M5-AC09. No acceptance row is newly complete.
Existing pre-release schema-1 workflow/ticket records require explicit
recreation; upgrade and recovery UX remain future M5 work. Real accepted-job
multi-page rendering, scheduler intake, installation, transport, and physical
printer evidence remain open. No administrator path, queue mutation,
transport, or printer was used.

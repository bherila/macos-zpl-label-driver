# CI design and runner policy — Tahoe baseline

## Active workflows

**ci.yml:** PRs to main, pushes to main and manual dispatch. `ubuntu-24.04-arm` runs repository/metadata checks and scope classification. Standard `macos-26` ARM builds/tests both Swift packages for code changes and exercises the inert diagnostic's local ad-hoc signature. Stable `ci-required` always aggregates expected results; a docs-only skip is deliberate and a missing/failed build fails closed.

**compatibility.yml:** manual repeat of `macos-26` ARM checks plus optional `macos-26-intel`. No macOS 13/14/15 matrix or backport work. Intel remains an optional candidate, not supported by successful compilation alone.

GitHub documents standard `macos-26` as ARM and a standard Intel counterpart [R31](REFERENCES.md#r31). Standard hosted use is free for public repositories, unlike larger runners and separately metered storage/services [R05](REFERENCES.md#r05) [R06](REFERENCES.md#r06). Use no paid runner classes or self-hosted printers in untrusted PR jobs. Keep failure artifacts small and short-lived, finite timeouts and superseded-run cancellation.

## Toolchain and deployment

Mac manifests declare `.macOS("26.0")` using Swift tools/language 6.0 as a conservative syntax baseline. The string form avoids requiring a newer manifest enum just to express the deployment target. `ci-swift.sh` requires host/SDK major at least 26 and exports `MACOSX_DEPLOYMENT_TARGET=26.0`. Future Xcode app/helper/installer settings must match; log and inspect actual built Mach-O deployment targets in M0/M5.

The OS runner label does not pin Xcode or the exact 26.x patch. Record `sw_vers`, native architecture, Xcode, SDK, Swift and runner image variables. M0 selects an available tested toolchain if stronger pinning is needed; do not guess an Xcode path. Newer-than-26.0 APIs require availability handling or a later explicit minimum decision. Current hosted 26.x evidence does not prove launch on every older Tahoe patch. Keep exact support rows truthful.

The portable core remains Linux-buildable. Initial Linux jobs do not assume a preinstalled Swift toolchain; native Apple frameworks and signing are validated on Mac. A pinned official Linux Swift job is optional later.

## Secret-free local signing

No Apple account, Developer ID certificate, Team ID, provisioning profile, notarization API or signing secret is needed. The Mac script builds, copies, ad-hoc signs, verifies and runs the inert diagnostic; no privileged installation or printer I/O occurs. This check belongs in PR CI because it contains no protected identity. Extend to all new executable/library/app components as they land, in the same PR.

Do not mistake code-signature verification for Gatekeeper/scheduler/helper acceptance. Those require recorded integration tests. Future trusted-public signing is separate, deferred and approval/secret-isolated; there is no silent fallback from a failed trusted release to local binaries.

## Coverage and protection

Add real filter/backend/UI/helper/installer build and test stages when implemented; do not treat missing targets as successful optional skips. The supplied checker is a lightweight offline guard, not a complete Actions validator. M0 must run actual GitHub workflows, test docs-only and deliberately failing-code paths, and validate YAML with a verified actionlint installation.

Require the observed `ci-required` check only after its first real run. Preserve protections and authenticated ownership. No auto-merge, protection bypass or paid capacity without explicit authorization.

Hosted tests do not qualify physical USB, cutter/peeler behavior, browser dialogs or clean retail installation. A host account reset is not a clean OS image. Keep those evidence levels distinct.

## Revision 3 portable accelerator

The native Mac job runs `scripts/run-accelerator-checks.py` in both configurations
through `ci-swift.sh`. It builds both new executables, runs the strict Python oracle
and the finite inert ABI cases. The fixture corpus is committed: ordinary CI uses
standard-library hashes/metadata checks, not pip-installed PDF renderers. Source
regeneration and optional barcode checks are separate development operations.
No experimental queue or backend is installed by CI.

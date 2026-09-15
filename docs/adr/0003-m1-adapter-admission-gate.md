# ADR 0003 — Defer production adapter selection pending Tahoe admission evidence

Status: accepted gate; adapter selection remains uncommitted
Date: 2026-09-15

The current Tahoe host preflight establishes that the scheduler is running and
that its configured binary directory is protected. It does not establish a
supported third-party filter/backend placement, scheduler admission of a
locally ad-hoc-signed executable, or an account-free authorization and rollback
path. Therefore the project will not install the custom-backend discard queue,
copy an executable into a scheduler directory, change `ServerBin`, restart the
scheduler, or select a production CUPS/IPP adapter on the strength of the
portable harness or a normal-user invocation.

Continue to use the existing inert CUPS ABI filter, discard-only probe, strict
option parser, synthetic fixtures, and profile snapshot contract as portable
preparation. Those artifacts may exercise source-level boundaries, but do not
establish M1-AC01 through M1-AC11 or M1-AC13. The existing cross-process lease
is likewise a portable mechanism until the chosen downstream boundary holds it
through actual scheduler-owned delivery.

Before selecting an adapter or performing an installation experiment, obtain
all of the following Tahoe-specific evidence:

1. A documented supported placement and invocation contract for the exact
   filter/backend or alternative framework, without changing global scheduler
   configuration.
2. A reviewable, narrowly authorized, reversible installation transaction that
   stages only experiment-owned artifacts with protected ownership and records
   rollback targets.
3. Scheduler execution after UI exit and a planned restart using local ad-hoc
   signing, with trust/admission observations recorded separately from
   `codesign` verification.
4. A discard-only queue proof for typed option propagation, complete synthetic
   input preservation, cancellation/error behavior, held-profile snapshots,
   and downstream lease lifetime.

The one permitted installation candidate for the M1 experiment is narrower than
the production-adapter decision: a root-owned, locally ad-hoc-signed absolute
filter path under the local printer directory and CUPS' existing
`file:///dev/null` backend. It generates a PPD from a supplied candidate by
replacing only its two PDF filter-program fields. This can establish scheduler
filter admission and UI/input observations without installing the custom
backend, touching `ServerBin`, transmitting to a device, or changing a default.
It remains a candidate until the reviewed transaction and Tahoe scheduler proof
have run; it does not select a production adapter or establish a supported
installer design.

An IPP printer application is not selected as a workaround. It remains an
alternative only after a separately reviewed framework/option-fidelity spike
and an explicit architecture decision. It must not be started merely to infer
native print-dialog behavior.

This decision links the read-only host preflight, local-signing boundary,
M1 acceptance checklist, and public CUPS contract reference ([host
preflight](../validation/M1-TAHOE-HOST-PREFLIGHT-2026-09-15.md), [local
signing](../LOCAL-SIGNING.md), [M1 acceptance](../milestones/01-printing-integration/ACCEPTANCE.md),
[R01](../REFERENCES.md#r01), [R34](../REFERENCES.md#r34)). It is M1-AC12
decision evidence only, not scheduler, hardware, installer, or release
acceptance.

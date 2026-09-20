# ADR 0005 — Queue installation transaction and privileged boundary

Status: **proposed**; decides no installation and authorizes none
Date: 2026-09-19
Decision owner: maintainer
Related requirements / acceptance IDs: M1-AC01, M1-AC06–AC08, M1-AC10, M1-AC11, M1-AC13,
M3-AC07–AC09, M4-AC12, M5-AC03, M5-AC05–AC08, M5-AC13. Issues [#129], [#123], [#89], [#80].

## Context and observed evidence

Observed on `main` at `a3f64c0`, 2026-09-19, by reading the tree:

- `ReferencePrinterSetupModel.canInstallQueue` (`ReferencePrinterSetup.swift:292`) requires three things:
  `stockLoadedConfirmed && tearOffConfirmed`, a workflow that validates, and an `.observed` stable
  identity on the profile's connection.
- Its **only** consumer anywhere in `Sources/` is a status icon (`ReferencePrinterSetup.swift:573`).
- There is no `installQueue`, `lpadmin`, `SMAppService`, `AuthorizationCreate`, `AuthorizationExecute`,
  `SMJobBless`, `cupsctl`, `NSXPCListener`, helper or installer anywhere in `Packages/LabelMac/Sources`.
  Each of those eight searches returns nothing.

So the gate guards a checkmark. [#123] makes the third conjunct satisfiable and thereby removes the last
unsatisfiable condition in front of **a path that has not been built**.

This corrects the framing carried in [#89] and in [#123]'s discussion, which said identity qualification
makes 23 criteria testable. It makes them *not structurally impossible*. The 17 installed-scheduler criteria
listed above still need an installation path to exist before any of them can be attempted.

What does exist is `scripts/m1-discard-file-sink.sh`, whose first comment line says it is
"deliberately not a product installer". It is a developer-only M1 experiment driven by `sudo -n` from an
interactive session, and it is valuable here for a different reason: it has already solved several of the
hard parts, and this ADR proposes to carry those over rather than rediscover them.

[ADR 0003](0003-m1-adapter-admission-gate.md) holds production adapter selection uncommitted pending Tahoe
admission evidence. **This ADR does not reopen that**, and nothing here selects an adapter.

## Options considered

**A. Promote the developer `sudo` script to the product path.** Rejected. `AGENTS.md` forbids collecting an
admin password and forbids `sudo` from a filter; a GUI app shelling out to `sudo -n` is neither supported nor
reviewable, and the script itself disclaims the role. It stays what it is: a developer-only baseline whose
reuse as a *conversion* baseline is explicitly different from production integration.

**B. Guided Installer package, no persistent privileged service.** One-shot, OS-mediated authorization
through a supported flow. No long-lived root process to authenticate clients to, which is the single hardest
problem without a Developer ID. Cost: a package is a coarse unit, uninstall needs its own mechanism, and
`LOCAL-SIGNING.md` is blunt that an unsigned outer `.pkg` around ad-hoc-signed payloads is **not** a
Developer-ID-signed installer and its admission flow must be tested, not assumed.

**C. Persistent privileged helper (`SMAppService` daemon plus XPC).** The most capable and the most
dangerous here. `LOCAL-SIGNING.md` forbids authorizing a root helper by bundle identifier, PID,
caller-supplied path, "signed code" or `anchor trusted`, because ad-hoc code can be re-signed by anyone, and
per-artifact hashes beside user-writable code are not provenance. Without a Team ID there is no evidenced
way today to authenticate a client to a root daemon. It also must not be adopted on API availability alone.

**D. One-shot privileged tool via Authorization Services.** Narrower than C, but the legacy
`AuthorizationExecuteWithPrivileges` route is not a supported design, and a bespoke one-shot tool still has
to answer the same "who may ask" question that defeats C.

**E. Unprivileged only — no system queue.** The app spools and delivers by itself. This abandons the
project's objective, which is the standard macOS Print dialog in every application, not a separate app.

## Decision (proposed)

**1. The app never holds privilege.** Privileged work is a separate, one-shot, OS-mediated operation. The
setup app plans and presents a transaction; it does not perform one. Document parsing and rendering stay
unprivileged, as `AGENTS.md` requires.

**2. Prefer B for the first product installation path; defer C.** A persistent helper is not adopted until
its account-free client authentication is *evidenced*, not asserted. If B proves unworkable on Tahoe, that
is a finding to record, not a reason to fall back to C by default. Never weaken privileged authentication to
compensate for the absence of a Developer ID.

**3. Installation is a transaction with a durable ownership record**, carrying over what the M1 sink proved:

- Capture preconditions, then stage under a protected root owned by `root:wheel`, then **validate after
  staging** — ownership, mode, absolute path, no symlink, content digest, and the local ad-hoc signature —
  because staging and validating are separate moments and the gap between them is a TOCTOU window.
- Write an ownership record naming every artifact the transaction created, so recovery is finite and
  manual recovery is possible from evidence rather than from guesswork.
- **Recover queue-first.** Remove the queue before the filter, so a partial failure never leaves a live queue
  pointing at an absent filter. The M1 sink already orders it this way and the product must too.
- **`lpadmin -p` is create-or-modify, not create-exclusive.** The transaction must detect a pre-existing
  queue of the same name and *refuse*, never silently adopt or modify one. Deleting or altering an existing
  queue is forbidden outright.
- Leave the default printer, unrelated queues and all global CUPS settings untouched.

**4. Unknown is never success.** Every state query is tri-state — present, confirmed absent, or *the query
failed* — and a failed query is never reinterpreted as absence. This is the M1 sink's existing discipline
(`queue_state` returns 0/1/2 and its comment forbids reading 2 as absence) and it is exactly `AGENTS.md`'s
rule that unknown capability or status is not false, zero, supported or completed.

**5. Uninstall is a first-class inverse, not a cleanup script.** Reversibility is a property of the design,
and it is the thing that makes an installation experiment safe to authorize at all.

**6. One physical-device coordination domain.** The lock is held by the delivery boundary — the
backend/coordinator that owns device lifetime — and not by the filter or the app. It is keyed to the
qualified stable identity from [#123], which is what makes "the same physical printer" nameable across two
queue names or connection aliases. Every product queue **and every maintenance action** joins that one
domain. A Swift actor is not a cross-process device lock, and a lock around conversion alone releases too
early, as `ARCHITECTURE.md` and the M1 spec both state.

**7. Explicitly forbidden, restated so a later slice cannot drift into them**: `sudo` from a filter; any
collected administrator password; a root shell service; changes to global CUPS security configuration;
writing to `/System`; disabling SIP or Gatekeeper; authorizing a helper by bundle identifier, PID,
caller-supplied path, "signed code" or `anchor trusted`; and a filter that depends on a user's home
directory or desktop interaction.

## Validation and migration

**Buildable now, inertly, with no privilege and no device.** A portable transaction state machine in
`LabelCore`, tested against the existing discard sink: tri-state query semantics and the refusal to read a
failed query as absence; refusal on a pre-existing queue name; rollback ordering under failure injected at
each step; the ownership record's round trip; and the assertion that an aborted transaction leaves no
artifact unrecorded. None of this touches CUPS, a device or a privileged operation.

**Blocked on the maintainer.** Any real installation is [#80] Part B — an interactive administrator session
with a frozen candidate, separately authorized. A green build never implies it. That gate is unchanged by
this ADR, and this ADR does not request it.

**Reconsideration triggers.** Tahoe refusing to admit a locally ad-hoc-signed filter; a package approval flow
that proves unusable without a Developer ID; a change in `SMAppService` acceptance rules that makes C
evidenceable; or the identity source of [#123] proving unstable on a second unit, which would return the
whole question to "which identity".

## What this ADR does not decide

It does not select an adapter — [ADR 0003](0003-m1-adapter-admission-gate.md) still holds. It does not decide
that a helper will ever be built. It qualifies no acceptance criterion, and it authorizes no installation,
no queue change, no privileged operation and no device access.

[#80]: https://github.com/bherila/macos-zpl-label-driver/issues/80
[#89]: https://github.com/bherila/macos-zpl-label-driver/issues/89
[#123]: https://github.com/bherila/macos-zpl-label-driver/pull/123
[#129]: https://github.com/bherila/macos-zpl-label-driver/issues/129

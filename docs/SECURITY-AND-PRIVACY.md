# Security and privacy design gates

## Trust boundaries

Untrusted inputs include PDF/image bytes, document metadata, queue options, profile imports, printer-discovery strings, device/status replies, connection endpoints, IPC clients and contributor-controlled CI code. The printer is not a trusted local computer just because it is on USB or the LAN.

Keep the renderer unprivileged, bounded and separate from installation. A malformed PDF must not be processed by root. Native framework calls need a real deadline/worker strategy where cooperative cancellation cannot interrupt them. Keep input/decoded-pixel/output limits distinct.

## Files and configuration

Use root-owned immutable installed executables with non-writable parent directories as required by the selected printing path. Validate actual paths and ownership on the target OS. No writes to protected `/System` locations. Shared published profiles are typed validated data readable by the spooler, not executable scripts and not references into `/Users`.

Use private quota-controlled job scratch, atomically created with restrictive permissions. Do not follow user-provided symlinks, use predictable world-writable names or expose arbitrary profile/template paths through job options. Define cleanup after success/failure/cancellation/crash and document any CUPS-managed spool retention separately from product-owned files.

## IPC and installation

Authorize each operation; authenticating an app alone does not authorize arbitrary commands. Validate client identity/signature where appropriate, request type, payload size, version, target ownership and destination. Pin installation to approved components and bundle identity/version. Guard against replacing a user-writable app between validation and privileged execution.

No generic `run(command:)`, `copy(source:destination:)`, environment-injected executable or unrestricted shell service. A helper must not trust arbitrary caller-supplied PIDs, paths, queue names or code-signing assertions. Partial installation uses a manifest/transaction so rollback cannot erase unrelated files.

SMAppService/service registration is one implementation option; verify its availability and approval semantics for the selected minimum macOS. Do not treat registration as permission to bypass authorization. The setup application never asks users to type an admin password into an application-controlled field. [R15](REFERENCES.md#r15)

## Device commands

Encode controls from typed ranges/enums. Reject untrusted control-prefix characters and line breaks where a constrained identifier is required. Do not concatenate display names, metadata or barcode payloads into administrative commands. No raw-ZPL fallback on failed PDF parsing. Advanced pass-through needs explicit opt-in and a documented trust boundary.

A printer profile is data, not a macro language. Automatic calibration, persistent save, factory reset, firmware update, file erase and unverified cutter/peeler activation are forbidden ordinary-job side effects. Limits and warnings must survive both UI and programmatic entry points.

## Network and status

Bind any product service locally by default with deliberate authorization, not 'localhost is always trusted'. Do not advertise network sharing without explicit opt-in and a threat review. Discovery is limited to supported local mechanisms; no broad IP scanning. Explicit raw TCP printing on a trusted LAN is not encrypted transport; disclose that limitation and avoid implying confidentiality it does not provide.

Bound reads, status frames, parse recursion and timeouts. Treat malformed or absent status as unknown/error, not healthy. Normalize a physical device identity without logging serials or relying on a mutable display name. Local coordination cannot serialize unrelated clients on another host.

## Diagnostics

Log IDs, error codes, profile revisions, dimensions, timing and state with sensitive fields excluded. No page images, barcode payloads, document titles, user names, home paths, serials or credentialed URIs by default. Even hashes may correlate private documents; expose only necessary identifiers and scope retention.

Full local diagnostic exports require opt-in, disclosure of included fields and review before sharing. They expire and can be deleted; never auto-upload them to an issue. Clearing visible text in a PDF does not prove the content was removed—prefer synthetic data at source.

## CI/release isolation

PR workflows are read-only, secret-free and use ephemeral standard hosted runners. No `pull_request_target` execution of contributor code, no untrusted PR on a self-hosted signing/printer Mac and no automatic command execution from issue text. Pin dependencies and validate forks without granting write tokens.

Local ad-hoc signing has no private identity and may be tested on ordinary ephemeral PR runners; it does not authorize privileged installation or public publication. Developer-ID signing, if later enabled, occurs only for trusted reviewed refs through a protected environment with least-privilege credentials. Keep exact mode/provenance visible and do not fall back silently between modes. [R16](REFERENCES.md#r16) [R18](REFERENCES.md#r18) [R28](REFERENCES.md#r28)

## Local-signing constraint

No Apple Team ID exists in the active signing mode. A matching bundle identifier or valid ad-hoc signature is insufficient privileged-client authentication. Rebuilding/re-signing can change code hashes; a user-writable allowed-hash list cannot safely authorize root code installation. Prove a narrowly authorized no-account installer path in M1, protect staged code against substitution and revalidate after staging. See [LOCAL-SIGNING.md](LOCAL-SIGNING.md).

Do not require users to trust a self-signed root, disable Gatekeeper/SIP, run a generic root shell service or strip quarantine automatically. Per-item OS approval, code verification, installer admission and explicit privileged authorization are separate test results. A source-built local artifact is not a notarized public binary.

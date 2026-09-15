# ADR 0002 — GC420d / Tahoe 26 / MIT / local signing

Status: accepted requirements; implementation and qualification pending
Date: 2026-09-15

The maintainer confirmed GC420d over USB, 4×6 pre-cut labels, tear-off/no cutter, Tahoe 26 as the minimum, MIT, and no Apple Developer account. Supersede ADR 0001's proposed older deployment target and license/signing assumptions; keep its uncommitted adapter decision.

Set deployment target 26.0 and standard hosted ARM runtime `macos-26`. No backport/older-runtime work is required. Keep portable Swift independently testable; optional Intel work must use a suitable 26 runtime and its own evidence.

Adopt certificate-free local ad-hoc signing as the default local mode. Account-free privileged installation feasibility joins M1's proof obligations; a Developer-ID-only architecture is not acceptable for the active scope. Preserve secure authorization/code-validation boundaries rather than weakening them. Trusted public binary signing/notarization is deferred.

Prioritize the named GC420d USB setup. Manufacturer facts are reference inputs; current unit settings, sensing and USB identity require observation. Use documented 8 dots/mm geometry instead of silently treating nominal 203 DPI as an exact pitch. Do not enable cutter/peeler/thermal-transfer options on the selected installation.

Keep baseline qualification separate from broader accessory/model parity, as defined in [release scopes](../RELEASE-SCOPES.md). Unavailable accessory hardware does not block the GC420d-local candidate and does not count as accessory evidence.

No installation, queue mutation, physical test or repository publication was performed or authorized merely by recording these inputs. Operational consent remains bounded and explicit.

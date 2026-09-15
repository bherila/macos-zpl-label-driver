# ADR 0001 — Swift-first engine with an uncommitted printing adapter

Status: proposed pending M1 integration evidence
Date: 2026-09-15

Use a portable Swift core and a macOS Core Graphics adapter, with native SwiftUI/AppKit setup. Prototype CUPS/PPD integration because the product requires full-fidelity page capture and native per-job controls. Do not approve that path until M1 demonstrates it on the intended OS/app matrix.

Keep IPP/PAPPL integration behind a separate boundary. Framework support for custom options is not proof of client UI exposure. Source/renderer/control/transport components must be reusable if the printing adapter changes.

There is no requirement to write a new USB stack, a custom IPP server, a kernel extension or a custom print-dialog plug-in. There is also no assumption that a terminal-only PDF converter satisfies product scope. Preserve the working raw queue throughout experimentation.

Platform/license/signing defaults were superseded by accepted ADR 0002: macOS 26.0 minimum, MIT confirmed, GC420d USB first and local ad-hoc signing. The adapter decision remains unproven. No printer compatibility is established by either ADR.

# M4 isolated document opening — 2026-09-16

Setup PDF opening now uses a reusable main-actor ownership model. Bounded
regular-file input runs in a detached task while its security-scoped access is
held. The existing layout worker handles PDF page discovery and all-page border
analysis under an explicit maximum of 32 pages. The original profile-building
logic consumes those checked facts; no Quartz document discovery/rendering runs
on the main actor in this product path, and no detection bitmap becomes print
source. The synchronous bootstrap remains for existing diagnostic tests only.

The private analysis request has explicit bounded page-limit/all-page fields;
legacy requests preserve their defaults. All-page requests cannot also name
specific pages. Returned page count and observed anchor presence are checked
against the request; existing source digest, geometry, byte and anchor ceilings
remain mandatory. An old worker ignoring the new mode cannot silently pass the
observed-fact contract.

Opening checks one 60-second cooperative budget, including read/scheduling time;
the child receives only remaining time. Filesystem calls are checked on return,
not forcibly interrupted. Unique request ownership and cancellation prevent
obsolete completion/errors from replacing newer state. Existing drafts survive
cancelled/failed replacement. Progress/Cancel Opening and persistent Open PDF
controls are connected to the setup app. Errors expose sanitized reasons rather
than paths/framework details. Opening creates an unsaved draft, not unattended
qualification or a printer queue.

Eighteen focused layout/bootstrap/opening tests passed. Real child output yields
the same native/Letter/A4 profiles as existing diagnostic bootstrap. Page limits,
invalid mixed all/specific requests, missing observed facts, cancellation,
unavailable worker and prior-draft preservation are covered. A finite barrier
pauses a completed real analysis while a newer editor installs, then verifies
the obsolete result cannot replace it. Full local `bash scripts/ci-swift.sh`
completed with exit 0: 67 Python, 166 Core and 178 Mac tests in debug/release,
132 independent round trips, all 15/10/1 ABI/inert cases, nested signatures and
packaged-worker equality. Publication is deferred: PR #50's parent-death worker
supervision finding must be addressed first. Hosted CI/review for this slice
have not run.

This advances automated resource/source fidelity evidence and implementation
toward M4-AC06/09; those integration criteria remain open. GUI/keyboard/VoiceOver,
window/process termination, actual sandbox/security-scope policy, quarantine,
installation, scheduler identity/intake, USB and physical labels are unverified.
No administrator, queue or printer operation occurred.

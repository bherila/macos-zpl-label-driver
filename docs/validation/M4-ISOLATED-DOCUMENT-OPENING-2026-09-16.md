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
have not run. After integrating lifetime fix `6ff328a` at local combined
commit `26ee086`, the full local gate passed again: 67 Python, 166 Core and
183 Mac tests in both configurations, all independent/ABI/inert checks,
ad-hoc signatures and packaged-worker equality. Publication remains held on
PR #50's live hosted CI and second review, not on missing local tests.

This advances automated resource/source fidelity evidence and implementation
toward M4-AC06/09; those integration criteria remain open. GUI/keyboard/VoiceOver,
window/process termination, actual sandbox/security-scope policy, quarantine,
installation, scheduler identity/intake, USB and physical labels are unverified.
No administrator, queue or printer operation occurred.

## Finite local GUI validation (not yet run)

On 2026-09-16 the UI automation entry point failed to start its runtime
(`failed to start Node runtime: No such file or directory`) before the setup
app opened. GUI inspection is NOT RUN. The failure is tooling evidence, not
an application launch failure; no GUI acceptance is inferred.

Use the locally built ad-hoc setup app and committed synthetic native, Letter,
A4, mixed-page and changed-layout fixtures only. No queue creation, privileged
installation, printing, or printer commands are authorized by this procedure.

1. Launch the app; confirm that media/tear-off acknowledgement gates editing,
   without claiming observation of the physical unit or changing its settings.
2. Open one native fixture using the Open PDF button, then one Letter/A4
   fixture using Command-O. Verify progress, responsive window movement, and
   an unsaved draft derived from the selected original document.
3. Start a replacement and cancel it. Verify that the previous draft survives.
   Open the mixed-page and changed-layout fixtures once each; verify a clear
   failure/manual-workflow message rather than a silently accepted wrong crop.
4. Request one preview, then change the selection or open a different fixture.
   Verify that an obsolete result cannot replace the new document's preview.
   Compare the displayed packed output with the emitted PBM, not a source
   thumbnail or a separate antialiased rendering.
5. With VoiceOver enabled, reach Open PDF, Cancel Opening and any failure
   message by keyboard. Verify accessible names, focus order, and non-color
   feedback. Record failures rather than changing acceptance criteria.
6. Close the app during one synthetic preparation. Confirm finite worker exit;
   relaunch once to inspect conservative scratch recovery. Do not recursively
   purge the temporary directory, scheduler metadata, or unrelated files.

Record exact commit, OS/build, app/worker signature identity, fixture hashes,
each observed result, and any retained scratch warning. Stop after this finite
sequence. These observations would support user-session GUI evidence only;
ordinary-application printing, scheduler admission, sandbox policy, installation
and physical label quality require their own prescribed validation.

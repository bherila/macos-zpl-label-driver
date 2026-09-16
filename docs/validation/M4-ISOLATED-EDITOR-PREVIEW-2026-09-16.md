# M4 isolated editor preview — 2026-09-16

The setup application's Preview button now uses original PDF bytes and the
existing extraction worker in a detached task. The portable planner snapshots
the selected region/profile on the main actor; native rendering and diagnostic
encoding occur outside it. The returned checked bitmap is the preview source.
There is no in-process UI rendering fallback when the worker is unavailable.
The synchronous model method remains available for existing diagnostic tests,
not the product Preview button.

Requests have unique ownership. Valid edits, selection changes, cancellation,
reload and view disappearance invalidate/cancel obsolete work. Completed results
must still match request, selection and immutable profile before publication;
obsolete errors cannot overwrite new state. Progress and Cancel Preview controls
are exposed, and errors omit paths/document/framework details.

The app builder now includes and individually ad-hoc signs/verifies the worker,
checks ARM architecture/build metadata and re-verifies it after bundle signing.
A mandatory finite synthetic smoke executes the packaged worker and compares
its complete PBM/ZPL with the release worker. It checks the 10x10 canvas and
byte counts. This is executable/protocol equality, not a new independent image
oracle or a GUI/install/Gatekeeper result.

Nine focused editor tests passed, including exact real-worker bitmap equality,
unavailable-worker rejection, processing/task cancellation and a deterministic
completed-obsolete-result race using the real child and a finite test barrier.
Full local `bash scripts/ci-swift.sh` completed with exit 0: 67 Python, 166 Core
and 172 Mac tests in debug/release, 132 independent round trips, 15 backend and
10 filter ABI cases, one inert pipeline case, nested local-ad-hoc signatures
and packaged-worker complete PBM/ZPL equality. Hosted exact-head CI and
independent review remain pending.
The negative packaged-worker check using `/usr/bin/false` returned the expected
exit 1 and sanitized failure message; it did not acknowledge invalid execution.

This advances automated M4-AC07 and implementation toward M4-AC06; the latter
still requires prescribed GUI/keyboard evidence. Setup PDF opening/bootstrap
analysis remains synchronous/in-process. Window/process termination, VoiceOver,
quarantine, clean-Mac install, scheduler identity/intake and physical labels
remain unverified. No queue, privilege, USB or printer operation occurred.

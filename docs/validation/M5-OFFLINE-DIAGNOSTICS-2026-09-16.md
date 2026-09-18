# User-initiated offline diagnostics

Partial M5-AC09/10 implementation and automated evidence only. No installed
scheduler, privilege, hardware or full diagnostic/accessibility acceptance.

The actual setup app exposes **Copy Offline Diagnostics**. It takes a synchronous
main-actor snapshot of its current models only when clicked. The report has a
fixed version/scope disclaimer and fifteen boolean state flags: setup/document
availability, opening/errors, uncertain import publication, manual/saved editor,
source reference and exact-preview availability. It contains no source bytes,
bitmap, barcode, titles, paths, option values, profile/queue/device identifiers,
raw exceptions, logs or arbitrary caller-provided strings. Missing models remain
unavailable, not passed. The report explicitly establishes no installation,
scheduler or hardware acceptance. This is a human-readable offline snapshot,
not a production status query or support matrix.

The action replaces the clipboard contents and reports the AppKit write result.
Its description warns that other apps and system clipboard services may share
copied text. The app itself does not upload the report; this is not a guarantee
against OS Universal Clipboard or third-party clipboard handling. No clipboard
data is read and no automatic diagnostic export/background service
is added. Public API provenance is [R37](../REFERENCES.md#r37).

PASS: three focused native tests, exit 0: unavailable models and fixed bounded
field vocabulary; actual opening-error presence without private-path or raw-error
export; real original-PDF manual opening, worker preview and saved revision
reflected accurately without exporting the workflow identity. No shared clipboard
is touched by tests. PASS: `swift build --package-path Packages/LabelMac --product
label-printer-setup`, exit 0. Native environment: macOS 26.6.2 build 25G83,
Apple Silicon, Swift 6.3.3.
PASS: full combined local `bash scripts/ci-swift.sh` at `9691a61`, exit 0:
67 Python, 173 Core and 247 Mac debug/release, both accelerator modes,
132 independent round trips, inert ABI/pipeline checks, local-ad-hoc signatures
and packaged-worker PBM/ZPL equality. The subsequent change only corrects the
UI privacy notice about system clipboard sharing. Correction `97c8a1c` passed
all three focused tests and `bash scripts/build-local-app.sh`, exit 0, including
local-ad-hoc executable/app/nested-worker verification and packaged PBM/ZPL equality.
Its local artifact is `artifacts/setup-app.8rTnRO/Label Printer Driver Setup.app`.
The full gate was not repeated for this UI-text-only correction; encoder,
snapshot and worker implementation are unchanged. Own hosted CI/review pending.

NOT RUN: clicking/copying/pasting through the GUI, keyboard/VoiceOver operation,
quarantined launch, installed diagnostics, scheduler integration or physical tests.
Keep the earlier finite manual editor procedure pinned to its supplied artifact;
this new action is not present in that earlier build.

Finite follow-up after publication: open this slice's recorded local artifact,
leave both hardware confirmations unchecked, click the copy action once and
paste into a local text editor. Check the version/disclaimer and state-only
fields; do not paste private application data or claim acceptance from the text.
One copy replaces the existing clipboard; perform it only when willing to lose
those contents. Quit without installing queues, submitting jobs or printing.

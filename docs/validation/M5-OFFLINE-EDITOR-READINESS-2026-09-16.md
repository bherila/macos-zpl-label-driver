# Offline editing and physical readiness are separate

Partial M4-AC06 and M5-AC01/04/10 implementation/automated evidence only.
No installation, scheduler job, device I/O or physical acceptance is added.

The fixed reference setup permits offline workflow editing before a printer is
attached or loaded. The app must not require inventing stock/tear-off observations
to inspect an original PDF and edit a draft. Both hardware confirmations still
start false; the view explicitly warns that they require actual observation.
Installation readiness independently requires both confirmations and an observed
connection identity. The current production reference factory has no discovered
identity, so queue installation remains unavailable under every confirmation
combination. Rendering bounds, immutable revisions and actual install/print
authorization boundaries are unchanged.

Five focused ReferencePrinterSetupTests passed. The new test uses an explicitly
synthetic typed identity to verify the four stock/tear-off combinations: offline
editing is available in all; installation readiness requires both. This is a
predicate test, not real discovery or permission to install. Existing tests retain
unobserved USB identity, qualified speed validation and unsupported/unknown
feature distinctions. Pre-merge implementation `753fa5a` passed the full local
67 Python/171 LabelCore/205 LabelMac debug/release gate, 132 independent round trips,
inert checks, local signatures and packaged-worker PBM/ZPL equality. The combined
gate at `079163a` after merging PR #56's historical-revision/stock/detector
corrections passed with exit 0: 67 Python, 171 LabelCore and 209 LabelMac tests
in debug/release; both accelerator suites, inert checks, local executable/app/
nested-worker signatures and packaged-worker PBM/ZPL equality passed. This slice's
own hosted CI/review are pending. Parent corrected run 35088390875 and second
review were still live at this checkpoint; no clean result inferred.

Subsequent PR #56 second-pass readback: the connector replaced its in-progress
reaction with a clean thumbs-up, with no new inline findings and all three prior
threads resolved. Base `55dd7d2` and head `e00a630` are unchanged. Hosted run
35088390875 remains live; PR #57 run 35088846529 and first review remain live.

## Native accessibility observations and correction

Earlier saved-reopening evidence described a nonempty AXWindows response as a
window observation. Stronger inspection contradicted that interpretation: its
element's AXRole was AXApplication, and bounded traversal found application menus,
not window controls. The earlier observation is too weak to prove an actual
window. No GUI pass was recorded, and no window/control acceptance is claimed.

The helper now requires an actual AXWindow and preserves its 4096-element bound,
deduplicates repeated references and waits finitely for startup. Direct executable
startup and a new-instance Launch Services request both failed that window check
on the previous `b836b42` artifact. No PDF, button, checkbox, print action or private
UI dump was used. Direct child instances were terminated/reaped. Launch Services
closure metadata initially remained false; a subsequent read-only inventory of
the exact test artifact namespace found zero app records and zero live matching
processes. No generic/preexisting app was terminated or adopted for cleanup.
Native AX trust returned true; this does not establish usable control access.
The cause of the missing verified window is unresolved, not attributed to a
product defect or to an assumed OS restriction.

The new offline gate still needs a real GUI check. Finite procedure: launch the
locally built app normally, leave both hardware confirmations unchecked, and
verify manual PDF opening is enabled while installation remains unavailable.
Open one committed synthetic Letter PDF, show its source reference, set a region,
generate its exact preview and close. Do not invent physical observations, install
queues or print. Inspect keyboard and VoiceOver operation separately. If the app
or bridge cannot show a window, preserve the failure and continue independent
work; do not relabel menus as a window or weaken the acceptance criterion.

## Stronger window observation on the combined build

Two new finite 15-second Launch Services probes used the combined `079163a`
locally built/signed app. Each requested a new instance, checked the returned
bundle against the exact artifact and excluded preexisting instance IDs. Both
observed one layer-zero WindowServer window owned by that instance's PID.
Only the matching count was recorded; no unrelated window title, payload or UI
dump was exported. This establishes an owned WindowServer window exists, not
onscreen visibility, a usable AXWindow, correct controls or application acceptance.
The earlier lack of a verified accessibility window is not proof the app failed
to create any window.

Accessibility still returned AXApplication/menus through AXWindows; the second
probe also found AXMainWindow, AXFocusedWindow and AXFocusedUIElement unavailable.
Both ended with the controls failure and without any button, checkbox, PDF or
print action. Each requested termination and, after a finite wait, force-termination
only of the acquired instance. Closure metadata remained false during that wait;
subsequent exact-artifact inventories each found zero app records and zero live
matching processes. The control-access cause remains unresolved. No source fix
or GUI/VoiceOver pass is inferred. The manual procedure above remains necessary.

## Finder-only finite manual check

Status: **NOT RUN; awaiting the maintainer's observations.** This roughly
five-minute offline check does not install queues or print. The maintainer was
given `artifacts/setup-app.x3Pkqf/Label Printer Driver Setup.app`, built from
implementation `7dd55d3` that passed the full local 67/173/243 debug/release,
signature and packaged-worker gate. A later build is a different artifact;
record which one was actually opened. Artifact directories are ignored local
outputs, not published downloads. `<checkout>` means the local repository folder.

1. In Finder press Command-Shift-G, enter
   `<checkout>/artifacts/setup-app.x3Pkqf`, and open **Label Printer Driver
   Setup.app**. Stop and record the exact message if launch is blocked or asks
   for administrator authorization. Do not weaken security or strip quarantine.
2. Leave both physical confirmations unchecked: **I loaded 4 × 6 inch pre-cut
   direct-thermal labels** and **This printer is in tear-off mode with no cutter**.
   Queue installation must remain unavailable; offline opening must be enabled.
3. Click **Open PDF for Manual Extraction…**. In the file chooser use
   Command-Shift-G to select `<checkout>/Fixtures/generated/letter-one.pdf`.
   Use this committed synthetic example, not a private shipping label.
4. Click **Show Source Page**. Require a source-page reference separately
   identified as not the print preview.
5. Set **Width (mm)** to `101.6`, **Height (mm)** to `152.4`, **Left (mm)** to
   `12.7`, then **Top (mm)** to `63.5`. Press Tab after each entry. Keep rotation
   **0°**. Shrink width/height before moving the starting full-page region so
   intermediate bounds stay valid. These are the supplied Letter fixture's
   4×6 region, converted from its original PDF points.
6. Click **Preview**. Require a nonempty black-and-white exact packed label
   preview without an error. Screen appearance is not physical/scanning evidence.
7. Quit with Command-Q. Saving is unnecessary. Do not click **Approve for
   Unattended Use**, install a queue, submit a scheduler job or print.

Return the artifact directory, OS version and these observations:

```text
App window visible: yes/no
Hardware confirmations stayed unchecked: yes/no
Queue installation unavailable: yes/no
Manual PDF opening worked: yes/no
Source reference appeared: yes/no
Crop fields accepted the values: yes/no
Exact preview appeared: yes/no
Keyboard/VoiceOver: observed result, or not tested
Errors or confusing behavior:
```

Tab navigation is a narrow observation, not a complete accessibility pass.
Keyboard and VoiceOver acceptance remain separate. If a screenshot is needed,
include only the synthetic example and relevant app controls; omit other windows,
private paths, printer identifiers and unrelated configuration. Do not convert
missing observations into a pass or check hardware criteria.

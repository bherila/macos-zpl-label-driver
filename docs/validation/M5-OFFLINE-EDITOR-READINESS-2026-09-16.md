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
gate after merging PR #56's historical-revision/stock/detector corrections and
this slice's own hosted CI/review are pending.

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

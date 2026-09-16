# Bounded source-page reference in the editor

Additional partial M4-AC06/07/09 implementation and automated evidence only.

The editor's Show Source Page action runs a full-page original-PDF render in the
existing supervised child. It requests independent physical-axis placement,
uniform source pitch and at most 1200 dots per axis; the validated packed bitmap
is at most 180000 bytes. Deterministic ordered dithering is for this monochrome
display reference only, not a change to the immutable job's imaging policy.
The existing PBM/diagnostic-ZPL validator checks the real child result.

The display is explicitly labeled source reference, not print preview. A dashed
region overlay follows canonical normalized bounds; the existing millimeter
controls remain the keyboard-accessible editing path. The original PDF remains
the final extraction source, and the exact packed label preview is separate.
Source requests have independent UUID/cancellation/error state, are invalidated
by selection changes, and are cancelled by replacement opening/view departure.
No profile, qualification, accepted bundle, job or delivery state is changed by
display rendering. Child-owned parent-loss/deadline supervision remains active.

Four focused native tests passed: real-child full-page equality across native,
Letter, A4 and ambiguous fixtures; dimensions/byte ceiling and no-fallback limits;
connected editor reference versus exact original-source region rendering; and a
finite barrier proving completed stale source output cannot survive a selection
change. The barrier uses real preparation, not a placeholder bitmap.
Full local gate, hosted CI and independent review are pending.

GUI/source-overlay alignment, keyboard/VoiceOver operation, display zoom and
direct mouse region selection are NOT RUN or unfinished. This does not complete
teach-once UI acceptance. Monochrome reference pixels are not color-document
fidelity or physical barcode evidence. No administrator, queue, system setting,
printer command or physical label was used.

# Finishing profile/device native-pitch binding — 2026-09-17

Partial M3 acceptance dependency only. FinishingDeviceGeometry retains a canonical
schema8 StoredPrinterProfile, opaque coordination domain and explicit native DotResolution
observation. Construction rehashes complete profile bytes, checks schema/revision/digest,
rejects unknown or unevidenced pitch, and bounds documented source identifiers separately
from lowercase queue selectors. GC420d native pitch must be8dots/mm on both axes, using
model facts in R26 and docs/hardware/GC420D.md; nominal203DPI is not substituted.

Canvas construction requires the queue's exact printer reference/device domain, complete
workflow/profile snapshot validation and reported nominal stock matching workflow output.
It uses native pitch with existing dot-rounding/allocation caps. Later canvas validation
requires complete equality, not equal physical dimensions alone. Generic native pitch is
explicitly declared, never guessed. Documentary and reported facts are retained distinctly;
no declared fact proves physical testing, discovered identity or unit correspondence.

Nearest independent constraints: exact profile bytes, coordination domain and model pitch
cannot be substituted while stock is unchanged. Eight focused/restored cases passed exit0,
including the five existing store cases and three new geometry cases: native813x1219 dots,
203DPI rejection, changed domain, forged profile digest, unknown/unevidenced pitch,
unsafe provenance, legacy role rejection and both GC420d pitch axes. Removing profile
hash, device domain or model pitch guards independently caused expected assertion failures
exit1; exact source restored and eight cases passed exit0. Initial unpublished compilation
required an explicit revision argument; provenance was then corrected to accept uppercase
reference IDs such as R26 rather than applying queue-selector rules. No published source
or acceptance criterion was weakened. Logs /tmp/zpl-finishing-device-geometry-focused.log,
/tmp/zpl-finishing-device-geometry-profile-digest-fault.log,
/tmp/zpl-finishing-device-geometry-device-domain-fault.log,
/tmp/zpl-finishing-device-geometry-model-pitch-fault.log and
/tmp/zpl-finishing-device-geometry-restored.log.
Source SHA256: 5026e81a47efff698a6587695b100fc08b16265979a6bbffa79b5bc9ec469671.
Full finite900s gate session56035 completed FULL_GATE_EXIT0:104Python/279Core/332Mac
in debug/release plus strict/ASCII oracles, bounded inert ABI/filter/pipeline checks,
ARM/min26 metadata, nested local signatures and packaged-worker PBM/ZPL equality.
Log /tmp/zpl-finishing-device-geometry-full.log; artifact artifacts/setup-app.TOGAq2.
Existing native CI includes new source/tests. Source publication pending.

Next: original-PDF worker analysis and immutable accepted finishing ticket binding complete
expanded order/copy/range ownership, verified queue/profile references, geometry and resolved
controls, then durable persistence/lifecycle. Unit identity/status, scheduler/privileged
admission and physical qualification remain open. Frozen Part B unchanged. No administrator,
printer I/O, merge or binary publication action.

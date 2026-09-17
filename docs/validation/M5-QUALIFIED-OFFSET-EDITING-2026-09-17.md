# Qualified signed offset draft editing — 2026-09-17

Partial automated implementation for M5-AC04/10 and M3-AC02/03/11. No manual
acceptance completion. Current unpublished source adds offset drafts to the setup
model and view, using the profile6 model intervals already bound into immutable jobs.

## Independent constraint and behavior

Invalid offset input must never become inheritance, a clamped value or a guessed
zero. A partial edit must retain independent configured offset, geometry, tracking,
motor and darkness defaults. Mark sensing requires its independently qualified
explicit offset; changing mode cannot silently drop that offset.

Three draft fields cover black-mark offset, horizontal shift and label top, with
signed whole-dot model intervals. Blank means per-field configured inheritance;
explicit zero is a real value. Invalid/fractional/non-finite/overflowing/out-of-model
text remains visible and blocks workflow/readiness rather than falling back.
Each control is shown only with its own supported evidenced range; facts distinguish
unknown current state from configured qualification and unsupported choices.
The reference GC420d profile exposes none of these unqualified controls.

Black-mark tracking requires a qualified explicit offset, including zero only when
chosen. Missing offset yields an actionable error. A supplied mark offset blocks
gap/continuous modes; clearing a draft field inherits the original bound default,
not a printer reset. Clearing an inherited mark offset or continuous length is not
represented by this optional-value API; incompatible inherited combinations fail
explicitly. No draft mutates the immutable profile or a printer setting.

The utility presents dot units, model minima/maxima, configured placeholders and
accessibility hints. Profile qualification does not become an observation of current
sensing or offset. Final signed containment remains the prepared encoder's shared
check; utility session validation alone is not packed-raster or physical proof.

## Validation

`swift test --package-path Packages/LabelMac --filter ReferencePrinterSetupTests`
passed ownexit0:24 tests, including four new offset cases. Coverage combines signed
edit/explicit zero with independent defaults, every invalid field class, mark
mode/offset qualification and unqualified reference rejection. Existing20 cases
remain. Hypothetical profile qualification is synthetic, not observed hardware.

Full finite 900-second `bash scripts/ci-swift.sh` gate passed ownexit0:89 Python/242 Core/296 Mac debug/release,132 original and180 ASCII independent round trips,finite benchmark/inert ABI/pipeline harnesses,ARM/minimum26 native metadata,nested ad-hoc signatures and exact packaged-worker PBM/ZPL equality. Local artifact:`artifacts/setup-app.vJmeVL`.
No GUI/keyboard/VoiceOver walkthrough, installed dialog, Tahoe26 host, queue/admin,
USB or physical action was run. B's approved frozen candidate remains unchanged.

## Remaining work

Persistent native profile/default management, system-dialog exposure, thermal and
finishing integration remain implementation work. M1 production adapter/helper/
lifecycle needs its prescribed evidence. Model capabilities and actual stock/state
must be qualified before physical claims. No merge or binary publication.

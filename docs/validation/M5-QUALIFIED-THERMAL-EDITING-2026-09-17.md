# Qualified thermal utility defaults — 2026-09-17

Partial M5-AC04/05/10 and M3-AC11 implementation; no acceptance completion.

## Independent constraint

A utility draft must preserve the effective configured thermal method and all
other immutable defaults without fabricating loaded-media/ribbon verification.
`ReferencePrinterSetupModel` starts from the configured method, exposes only
separately supported evidenced profile7 model methods, and returns the actual
resolved method after validating the ordinary encoder. Clearing a selection
inherits the immutable configured default. If profile7 has none, the explicit
method requirement remains; no silent direct-thermal fallback.

Supported but incompatible selections stay visible as drafts and block save/
installation readiness with actionable media/ribbon errors. They do not rewrite
consumable declarations, qualification or confirmation flags. Unknown support
and unsupported methods are not choices and are explicit support facts. Separate
model-support, declared-media and declared-ribbon rows distinguish supported,
unsupported, unknown and observed absence. Supplied installation declarations
are labeled as declarations, not authenticated sensor observations or physical
qualification. Profile7 stock text no longer claims direct-thermal stock for
transfer profiles. Legacy GC420d remains direct-only with unchanged confirmations.

The native picker supplies configured inheritance and qualified choices with
an accessibility hint and declaration explanation. It edits utility drafts only;
no printer command or installed queue/default mutation occurs. Changing declared
consumables requires a separately verified profile revision; selecting a method
or checking readiness boxes cannot fabricate those facts.

## Automated evidence

Initial37 focused setup/editing tests passed own exit0, including five new
`ThermalPrinterSetupTests`: configured transfer with motor/darkness-zero/geometry/
offset preservation, retained incompatible selection and inheritance, unknown
support/default rejection, unknown media/ribbon despite confirmation flags, and
immutable transfer save/restart with invalid-save draft retention. New model-support
fact rows and an explicit unknown-support assertion were added before the full
gate reached native compilation; portable sources stayed unchanged. Full finite
900-second `bash scripts/ci-swift.sh` gate passed own exit0:
89 Python/256 Core/313 Mac debug/release, 132 original and180 ASCII independent
round trips per mode, finite benchmark/inert ABI/pipeline harnesses, native ARM
and minimum26 metadata, nested ad-hoc signatures and packaged-worker PBM/ZPL
equality. Local artifact: `artifacts/setup-app.9WdCIQ`. This is automated
evidence, not GUI/keyboard/VoiceOver/scheduler/physical acceptance. The full native
suites include the revised explicit model-support fact assertions. Deliberately
forcing direct thermal in the utility made the configured-transfer composition
case fail own exit1. Source restored byte-for-byte (SHA256
185c65f64d980dd67b474c4b897a181675e1f8549c8adf56d607eedea2def1e1);
all37 restored focused cases passed own exit0.

## Remaining implementation and evidence

Manual GUI picker/save/reopen, keyboard and VoiceOver walkthrough remain NOT RUN,
as do Tahoe26 runtime qualification and other-model native pitch/model admission.
No GC420d transfer capability is enabled: transfer fixtures are explicitly synthetic.
Finishing/accessory policies, production M1 adapter/privileged identity/lifecycle,
installed queue/default/system-dialog management, USB, faults and physical control
isolation remain open. Source compilation and inert encoding do not prove actual
media/ribbon state or printing. No printer/admin/merge/release/binary publication.
Part B frozen candidate unchanged. Protocol semantics retain public R45 provenance
and the immutable thermal policy/job binding evidence; no new device command.

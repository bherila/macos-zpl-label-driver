# Evidence — Issue #80 Section A offline GUI check, executed

- Date/time and operator: 2026-09-18, approx. 22:05–22:20 local (America/Los_Angeles).
  Maintainer-supervised assistant session driving the local GUI through the desktop
  accessibility/computer-use bridge. Every action below was taken on the maintainer's
  own Mac with per-session approval.
- Exact repository commit SHA: `d6f03d75e48baef4a9afb10333f2d73987cf93ff`
  (worktree `macos-zpl-label-driver-main-audit`, clean working tree).
- Related requirement and acceptance IDs: M4-AC06, M5-AC01, M5-AC04, M5-AC10
  (partial, see below). Referenced by issues #80 (Section A) and #89.
- Evidence level: I — macOS integration, GUI, no installed scheduler.
- Status: **PASS for the Section A procedure; FAIL/OPEN on four separate GUI defects
  recorded below.** No acceptance ID is closed by this run.
- macOS/architecture: macOS 27.0 (26A428) on an M1 MacBook Pro, arm64, as reported by
  the maintainer. The app declares `LSMinimumSystemVersion` 26.0, so this run exercises
  it one major version above its declared minimum; nothing here is evidence for 26.x.
  Display used was the external "LG Ultra HD" (3360 x 1860 logical). Swift/Xcode not
  applicable; no build was performed here.
- Application/version: `Label Printer Driver Setup` 0.1.0 (build 1),
  `net.bherila.label-printer-driver.setup`, `LSMinimumSystemVersion` 26.0,
  `LabelDriverSigningMode` `local-ad-hoc`.
  Artifact: `artifacts/setup-app.OMnQLU/Label Printer Driver Setup.app`, supplied
  already-running by the maintainer. `Contents/MacOS/label-printer-setup`
  sha256 begins `768126bbc0f8755c587ff125`, mtime 2026-09-19 02:43 UTC.
  The artifact's provenance was **not** independently re-derived from the SHA above.
  Path used: the system print dialog was never involved; this is the app's own
  manual-extraction path only.
- Printer model / transport / stock: none attached. Read-only USB discovery reported
  no printer-class interfaces (see Observation 7). Reference setup is the fixed
  GC420d / USB / 4 x 6 in pre-cut direct thermal / tear-off / no cutter baseline.
- Fixture ID/hash: `letter-one`,
  `e825068f01b1a5b0ca1ccfba881851506ffa4f0eec764bbaf5ecea587af24cb5`,
  matching `Fixtures/catalog.json`; generator `tools/fixtures/generate.py`.
  Expected region from `Fixtures/generated/manifest.json`:
  `rawRect [36, 180, 288, 432]` PDF points on a 612 x 792 pt page, payload
  `LPD-TEST-A-001`. That is exactly Left 12.7 mm, Top 63.5 mm, Width 101.6 mm,
  Height 152.4 mm, which is the value set this issue prescribes.
- Profile/job-ticket revision/hash: no revision was saved; no workflow was approved.
- Explicit hardware/installation authorization and budget: **none requested and none
  used.** No queue was installed, no job submitted, no printer command sent, no
  administrator prompt accepted, no security setting changed, nothing printed.
  Both hardware confirmations were left unchecked throughout.

## Procedure

Executed against the already-running app supplied by the maintainer:

1. Enumerated the app's windows over the accessibility bridge. One main window was
   present and reachable; the `cgWindowNotFound` failure recorded in earlier attempts
   did **not** recur in this session.
2. `File > New Label Printer Driver Setup Window` to look for a clean surface, then
   closed that window again (see Observation 5).
3. Confirmed both hardware confirmations were unchecked and that the view showed
   `Queue installation remains unavailable until this Mac positively identifies the
   USB device`.
4. `Open PDF for Manual Extraction...`, navigated with Command-Shift-G to
   `<worktree>/Fixtures/generated/letter-one.pdf`, opened it.
5. Set the region bounds, in the order the existing readiness note prescribes
   (width and height shrunk before the origin is moved): Width `101.6`,
   Height `152.4`, Top `63.5`, Left `12.7`. Rotation left at 0 degrees.
6. Clicked `Preview` and inspected the generated exact preview at magnification.
7. Clicked `Show Source Page` and inspected the monochrome source-page reference.
8. Tab-traversed the bounds fields and the region list.
9. Clicked `Discover USB Printer Interfaces` (read-only by its own description).
10. Reopened the same fixture to test whether the states in Observations 3 and 4 reset.
11. Left the app running. No revision saved, nothing approved, nothing installed.

## Expected and observed results

**Section A oracle — met.** The four fields accepted `12.7` / `63.5` / `101.6` /
`152.4` and retained them. `Preview` produced a nonempty black-and-white exact
preview whose content matches the fixture's declared region: heading
`SYNTHETIC TEST LABEL`, `Fixture A - NOT VALID FOR SHIPPING`, `LABEL A`,
`TEST RECIPIENT - NO REAL ADDRESS`, the QR block, the Code-128-style barcode
captioned `LPD-TEST-A-001`, and both `BOTTOM LEFT` / `BOTTOM RIGHT` corner markers
present and upright. Orientation and corner markers being intact is consistent with
an unrotated, unclipped crop of the declared 4 x 6 region. This is screen appearance
only; it is not scanning, packed-bitmap or physical evidence.

The Section A report template answers, for the record:

```text
App window visible: yes
Hardware confirmations stayed unchecked: yes
Queue installation unavailable: yes
Manual PDF opening worked: yes
Source reference appeared: yes
Crop fields accepted the values: yes (see Observation 6 on decimal entry)
Exact preview appeared: yes
Keyboard/VoiceOver: Tab traversal partially observed; VoiceOver NOT tested
Errors or confusing behavior: see Observations 1-6
```

### Observation 1 — raw enum case is shown as the user-facing error (defect)

After the exact preview is invalidated, the editor displays the literal string
`editSnapshotChanged` in red, directly above the `Preview` / `Save Revision` row.
This is an internal identifier, not a sentence, and it is the only indication of the
state. Reproduced twice. Relevant to M5-AC10, because the state is carried by red
text alone with no icon, no shape and no plain-language explanation.

Post-run source check: `WorkflowEditorModel.report(_:)`
(`WorkflowEditor.swift:490`, landed in `78acd9b`, PR #100) maps this case to
`The draft changed. Review the current values before editing again.`, and that
literal **is present in the tested binary**, so the artifact is not older than the
fixed-vocabulary change. `lastError` is assigned only localized strings, and the two
error labels in the editor view (`:578`, `:819`) render it directly. The code path
that produced the raw case name on screen was therefore **not identified by reading
the source** and needs a debug reproduction. Do not close this by inspection.

Second instance, observed later the same session: after the GC420d was attached and
read-only discovery was re-run, the same red label in the same position showed
`invalidNormalizedRegion`. That is `LabelCore.PageGeometryError.invalidNormalizedRegion`
(`PDFPageGeometry.swift:7`), and `report(_:)` explicitly handles `PageGeometryError`
at `WorkflowEditor.swift:515` with
`Enter finite, positive dimensions and keep the region within its source page.`
Both that literal and every other branch of the mapping are present in the shipped
`.app` binary **and** in `Packages/LabelMac/.build/out/Products/Release/label-printer-setup`.
So two unrelated error domains both reached the UI as raw case names from a build
that contains the correct mapping. `lastError` is `private(set)` and every assignment
to it in `Sources/` is a localized string, so a second error surface is suspected but
was not located.

Artifact attribution caveat: the four running processes of this bundle identifier all
reported `isRunningFromDevPath: true`, so the exact on-disk image behind the driven
window was not positively tied to the `.app` bundle hashed above. Re-run this
observation against a known-provenance build before triaging.

### Observation 2 — pluralization defect

`1 regions require review before unattended approval.` appears beside the disabled
`Confirm Bounds and Exact Preview Reviewed` control.

### Observation 3 — the approval row is not rendered while the source-page reference and the exact preview are both shown (defect)

With the exact preview shown and the source-page reference hidden, the row
`Confirm Bounds and Exact Preview Reviewed` / `Preview` / `Save Revision` /
`Approve for Unattended Use` is present. Once `Show Source Page` is used and a
preview is present, that entire row is absent from the rendered window. It is not
merely clipped: it was still absent after scrolling to the end of the scroll view,
and still absent with the window zoomed to the full 3360 x 1860 display. The
`Show Source Page` button does not change its label and pressing it again did not
hide the reference. Consequence: in that state the reviewed draft cannot be
confirmed, saved or approved.

The row returns when the preview and the reference are discarded (Observation 4) or
when the document is reopened, so the condition is sticky per open document rather
than permanent. Note that the finite procedure in
[M5-OFFLINE-EDITOR-READINESS-2026-09-16](M5-OFFLINE-EDITOR-READINESS-2026-09-16.md)
ends by quitting without approving, so that procedure does not surface this; a user
who actually wants to save a manually taught region does.

### Observation 4 — exact preview and source reference are discarded by a focus change alone (defect)

Moving keyboard focus into or out of a bounds field discards both the generated exact
preview and the source-page reference and sets the `editSnapshotChanged` state, even
when no field value changes. Reproduced by Tab and by clicking a field. A reviewer can
lose a reviewed preview without editing anything.

### Observation 5 — transient layout collapse (anomaly, not characterised)

Immediately after `File > New ... Window`, and again immediately after opening a PDF
for manual extraction, the window rendered with the left setup column overlapping or
failing to paint under the editor column, with fragments of the left column's labels
drawn beneath the editor. In each case the layout corrected itself on the next layout
pass caused by interaction. Not reproduced deterministically enough to attribute a
cause; recorded so it is not lost. A separate coordinate-offset mistake by the
operator during the second attempt is explicitly **not** part of this observation.

### Observation 6 — intermittent loss of the fractional part on entry

Typing `101.6` and `63.5` into the bounds fields committed as `101` and `63` on the
first attempt in two instances; retyping the identical value immediately afterwards
committed correctly. Suspected formatter round-trip during keystroke handling. A user
can silently end up with a whole-millimetre bound.

Post-run source check, probable root cause: `measurementField`
(`WorkflowEditor.swift:823-835`) uses `TextField(value:format:)` with
`format: .number.precision(.fractionLength(0...2))` over a `Binding` whose `set`
commits to the model on each parse and whose `get` re-formats from the model. An
intermediate keystroke such as `101.` parses to `101`, the model commits `101`, and
the field re-renders as `101`, discarding the pending fractional digit. That is
consistent with the intermittent behaviour observed and with it succeeding on retype.
The same construct is the reason the documented "shrink width and height first" rule
exists: each keystroke is a committed edit, not a deferred one.

The separate, documented behaviour
whereby setting Left or Top before shrinking Width or Height reverts the entry to `0`
was also seen and is **not** treated as a defect here — it matches the existing
readiness note — but it reverts silently, with no message explaining why.

### Observation 7 — read-only discovery and installation gating behaved correctly

`Discover USB Printer Interfaces` reported:
`No printer-class USB interfaces were exposed by this registry scan. This is not proof
of physical disconnection.` Both hardware confirmations started and remained unchecked.
The reference setup surface states `Queue installation remains unavailable until this
Mac positively identifies the USB device`, and no installation affordance was offered
under that condition. Each reference-setup row carries a distinct glyph (check,
question, prohibited) alongside its text, so that surface does not rely on colour alone.

### Observation 9 — GC420d attached: printer-class interfaces are observed, installation stays gated

Added after the maintainer attached the GC420d over USB and approved the macOS
`Allow accessory to connect?` prompt for `Zebra Technologies ZTC GC420d (EPL)`.
Re-running `Discover USB Printer Interfaces` changed the result from the no-device
text in Observation 7 to:

`Printer-class USB interfaces observed. Model, stable identity and transport remain
unqualified.`

A new `Session-only USB interface observation` pop-up appeared, defaulting to
`No observation selected`. With no observation selected, the reference setup still
showed `Transport: USB — device not discovered` and the warning
`Queue installation remains unavailable until this Mac positively identifies the USB
device` was still present. Selecting an observation was **not** exercised in this
session. This establishes that the read-only discovery path sees a real Zebra device
and continues to refuse to infer model, identity or transport from that, which is the
documented intent. It does not establish queue installation, identity qualification or
any device I/O, and nothing was sent to the printer.

**Selecting the observation was then exercised.** The pop-up offered exactly one
entry, `USB VID 2,655, PID 209, interface 0` — decimal 2655 is `0x0A5F` (Zebra
Technologies) and 209 is `0x00D1`, consistent with the attached GC420d EPL. Selecting
it changed nothing in the reference setup: `Transport` still reads
`USB — device not discovered`, and the queue-installation warning is unchanged. That
is by design, and the surface says so: *"Selection does not qualify a GC420d, save a
connection, authorize installation or send printer commands."*

**Consequence for issue #89, verified in source.** `ReferencePrinterSetupModel.canInstallQueue`
(`ReferencePrinterSetup.swift:292`) requires `profile.connection.stableIdentity` to be
`.observed`. Across both packages, `stableIdentity` is only ever constructed as
`.unobserved` in `Sources/` — the GC420d factory at `PrinterProfile.swift:539` — and
`.observed` appears only in test fixtures. The code comment states the gap directly:
*"Installation remains unavailable until a later bounded discovery flow supplies an
identity."* That flow is not implemented.

Therefore queue installation cannot be reached in this build by any user action, on
any Mac, with the printer attached or not. The seventeen "installed scheduler"
criteria and the six application-path GUI criteria in issue #89 are blocked by
**unimplemented identity qualification**, not by test-Mac access, administrator
rights or hardware availability. Attaching the printer was still worth doing: it
establishes that read-only discovery sees a real Zebra interface and that the gap is
the qualification step alone.

Minor defect noted here: the pop-up renders the USB vendor ID with a locale thousands
separator (`2,655`). An identifier should not be number-formatted, and the decimal
rendering is also harder to check against the usual hexadecimal `0x0A5F`.

### Observation 8 — keyboard and accessibility, narrow

Tab moved between all four bounds fields, selecting each field's contents, and
continued into the region outline list, which took a visible selection. Buttons were
not observed taking Tab focus in this session; the machine's Full Keyboard Access
setting was not recorded, so nothing is concluded from that. The bridge used for
inspection redacts accessibility titles, so **this session cannot assess whether the
controls expose correct accessibility labels**, and no claim is made either way.
VoiceOver was not run. M5-AC10 remains open.

## Artifacts

Screenshots of each step were reviewed live in the session and are not committed here;
they would show only the synthetic fixture and app controls. No clipboard diagnostics
report was captured: clipboard access was not granted for this session, so
`Copy Offline Diagnostics` was not exercised. No private payload, printer identifier
or unrelated window content was exported.

## Limitations / next action

- No acceptance ID is closed. M4-AC06 still lacks region reorder (`Move Earlier` /
  `Move Later` stay disabled with a single region), save, and reload-and-correct.
  M5-AC04 still lacks a full walk of the qualified controls and utility defaults.
  M5-AC10 still lacks VoiceOver and an accessibility-label inspection that is not
  performed through a title-redacting bridge. M5-AC01 was exercised only as far as
  launching and using the app without terminal commands, an Apple account, an
  administrator prompt or any weakening of OS security; the installation itself was
  not exercised.
- Issue #89's ten "GUI testing" criteria do not all become reachable on a test Mac.
  M1-AC02, M1-AC03, M1-AC04, M1-AC05, M4-AC10 and M6-AC03 all depend on printing
  from real applications through an installed virtual queue, and this build refuses
  queue installation until a USB device is positively identified. On this host, with
  no GC420d attached, they remain blocked by **hardware**, not by GUI access or by
  administrator rights. Only M4-AC06, M5-AC01, M5-AC04 and M5-AC10 were reachable
  offline today, and none of them closed.
- Issue #80 Section B (administrator M1 experiment) remains **NOT RUN**. It was
  explicitly out of scope for this session; nothing in this run authorises it.
- Section C physical qualification remains out of scope and unauthorised.
- This run covers exactly one host configuration: macOS 27.0 (26A428) / arm64 / M1.
  It is not compatibility evidence for macOS 26.x, for Intel, or for any other display
  scale, and M6-AC03 is untouched by it.
- Next: fix or triage Observations 1-4 and schedule a separate VoiceOver pass before
  claiming M5-AC10.

## Addendum — 2026-09-19, added when this record was committed

Everything above is the original session's record, committed verbatim. It sat untracked in a detached
worktree on the maintainer's machine for a day and is committed now so the only record of a real GUI
session is not lost. This addendum was written by a later session that did **not** witness the GUI run and
has not re-observed any of it on screen.

**One internal contradiction, and which statement stands.** The record was appended to as the session went
on. Its header (`Printer model / transport / stock: none attached`) and the second Limitations bullet
(`with no GC420d attached, they remain blocked by hardware`) were written before the printer was attached.
Observation 9 was written after, and supersedes both: the six application-path criteria and the seventeen
installed-scheduler criteria are blocked by unimplemented identity qualification, not by hardware. That
conclusion was verified against the source independently and is recorded on issue #89.

**Disposition of each observation.**

| Observation | Since |
|---|---|
| 1 — raw enum case names | **Unresolved.** `report(_:)` was `String(describing:)` until `78acd9b`, which produces exactly these strings, but this record shows the hashed bundle already contains the mapping. With four processes running from development paths, the driven window was never tied to that bundle, so an older process is the leading explanation and it is not proven. #118 stamps the source revision into `CFBundleVersion` so a recurrence can be tied to a commit, and adds the missing `PageGeometryError` test. |
| 2 — pluralization | Fixed in #118; summaries moved to the model and tested. |
| 3 — approval row unreachable | Fixed in #118 on a positional diagnosis: the pane is capped at 720 points inside the setup window's own scroll view, so zooming grants it no height, and the preview image had no maximum height. The controls are now pinned below the scroll view. **Not re-observed on screen.** |
| 4 — focus change discards the preview | Fixed in #118 by two guards, one in the model and one in the field; tested. **Not re-observed on screen.** |
| 5 — transient layout collapse | Open, uncharacterised: issue #119. |
| 6 — decimal entry loses the fraction | Fixed in #118: the field commits on submit or focus loss rather than per keystroke. **Not re-observed on screen.** |
| 9 — vendor ID rendered `2,655` | Fixed in #118; identifiers are formatted as hex. |
| 9 — installation unreachable | Identity qualification implemented in #123, held for maintainer review. Note that no install action exists behind `canInstallQueue` yet; it drives only a status icon. |

Four of the fixes are compiled and unit-tested and have never been seen on screen. Confirming them needs a
supervised GUI session against a bundle whose stamped revision is at or after `201ab1c`.

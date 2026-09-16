# Explicit manual document intake

Partial M4-AC01/05/06/09/13 implementation and automated evidence only.
Implementation commit: `f9db898750cfb897c8b56fd2421a8d9ce09a7c37`.

An explicit Open PDF for Manual Extraction action (Command-Shift-O) uses the
existing bounded original-document worker for page geometry, without requiring
border detection. Assisted opening remains the default and still rejects
borderless/ambiguous matches. Manual mode is never an automatic failure fallback.
Every page, including mixed-size and instruction pages, starts with one full-page
editable region, its actual expected geometry, and explicit output order. No page
is silently dropped and no carrier crop is guessed. The stock remains reference
4x6 at model-documented 8 dots/mm. The draft is unsaved and unqualified, with a
visible review notice. Empty structural checks continue to reject unattended
qualification, and the corresponding UI action is disabled.

The new edited-draft regression initially failed: reloading a normalized region
changed one coordinate by one ULP and produced `profileConflict`. A finite native
Foundation reproduction isolated retained decimal NSNumber conversion. The codec
now parses only NSDecimalNumber's decimal string, preserving ordinary binary
NSNumber bits. Universal string conversion was tested and rejected because it
shortened existing physical dimensions. Exact model equality and canonical byte
identity remain strict; no tolerance or golden changes hide the defect.

Six codec tests and 15 bootstrap/opening tests pass on native macOS. New cases
cover neighboring fractional coordinates, canonical byte stability, borderless
Letter edits rendered through the real child, exact packed preview, persistence,
missing-check qualification rejection, ambiguous/mixed/non-label page accounting,
and explicit manual selection versus default no-match failure. Full local
`bash scripts/ci-swift.sh` passed: 67 Python, 167 Core and 187 Mac tests in
debug/release, 132 independent round trips, 15/10/1 ABI/inert cases, ad-hoc
signatures and packaged-worker PBM/ZPL equality. Hosted CI and independent review
have not run for this slice.

GUI inspection remains NOT RUN because the automation runtime failed before
launch. Region controls are numerical; source-page visual selection, save/reload
GUI round trips, accessibility and physical workflow acceptance remain required.
No queue, administrator, transport, printer command or physical label was used.

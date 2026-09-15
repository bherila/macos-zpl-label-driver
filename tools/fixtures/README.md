# Original synthetic regression fixtures

Committed inputs are ready to use; installing Python imaging/PDF packages is
**not required for normal Swift builds or CI integrity checks**.

The generator is development-only. It is not part of the runtime PDF renderer,
which remains a native Core Graphics implementation to build during M2.

```sh
python3 -m venv .venv-fixtures
. .venv-fixtures/bin/activate
python3 -m pip install -r tools/fixtures/requirements.txt
python3 tools/fixtures/generate.py --replace-generated
python3 scripts/check_fixture_manifest.py
```

Pin files describe the environment used for handoff generation, not a claim that
they are the latest dependency versions. Do not bundle these packages in the
Mac driver. Review future upgrades and resulting fixture hashes deliberately.
The generator overwrites only its named generated outputs after the explicit flag.

## Concrete inputs

18 PDFs / 28 pages plus three self-contained HTML print fixtures. They cover
native 4x6, Letter/A4 extraction, multiple regions, page rotation, positive and
negative box origins, UserUnit 1/2, transparency, fine rules/text, embedded raster,
mixed-size documents, an interactive form widget with a validated appearance,
non-label pages, changed layouts, ambiguous regions, and A/B/C order. The catalog
marks families `available-partial`, not fully complete.

The vector label includes Code 128 and QR symbols with explicitly synthetic
payloads. HTML contains an inline vector Code 128 and no network assets or JS.
Neither type copies an actual courier site's layout or constitutes evidence of
live shipping-site compatibility. PDF text uses standard base-font references;
no font files are bundled. Fonts and text rasterization can vary by renderer.

`annotation-form.pdf` contains one canonical AcroForm text field and one Widget
annotation with a nonempty normal appearance stream. The generator reopens and
checks both the field value and widget appearance. The renderer's supported
contract is explicit rejection; this fixture does not authorize silent flattening.

`Fixtures/generated/manifest.json` contains SHA-256, source regions, normalized
upright regions, boxes, rotation, UserUnit and expected barcode payloads. The
coordinates are **fixture ground truth**, not a shipped template-selection engine.
For the changed-layout fixture, the actual region intentionally differs from the
original Letter template; a paper-size-only matcher should not accept it.

`small-text` deliberately contains fine text/rules. Low-resolution checker images
are intentional adversarial content; the raster fixtures' barcodes remain vectors.
Reduced labels on four-up sheets must be extracted from the original PDF before
final-resolution rendering. Whole-sheet low-resolution barcode decoding is not
an acceptance substitute for that path.

## Optional deeper source validation

The preparation run used pypdf for structure, Poppler `pdftoppm` for rendering,
and pyzbar/ZBar for source barcode decoding. `validate_sources.py` repeats that
check when those optional tools are installed. It never sends labels to a printer.
Install `pyzbar==0.1.9` in the development environment; Poppler and ZBar are native
external test tools, not bundled dependencies. Missing tools fail the explicit
validation command rather than returning a false pass.

```sh
python3 tools/fixtures/validate_sources.py
```

The decoder expects both symbol families and payloads at **500 nominal DPI of
whole-page source rendering**. This establishes source-fixture consistency, NOT
barcode readability after our yet-to-be-built renderer or at the printer.
The validation report records actual raster dimensions so UserUnit behavior
cannot be inferred from a DPI flag alone. Future renderer comparisons must assert
physical dimensions independently.

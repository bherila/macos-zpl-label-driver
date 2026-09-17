# Third-party notices and provenance

No third-party runtime source is vendored in the current implementation. Apple SDK frameworks are system dependencies, not relicensed by this repository. GitHub Actions are development dependencies referenced by immutable commits. The Swift toolchain is externally supplied.

Before adding a dependency, record: source URL, exact version/commit, SPDX license, bundled components, modifications, required notices, whether it is shipped or build-only, and why it is needed. MIT on this repository does not override another component's license. Review obligations before incorporating copyleft code or distributing linked binaries.

Do not add proprietary third-party driver software, extracted resources or PPDs. Do not redistribute documentation PDFs or local font files merely because they are accessible. Public protocol documentation can be linked and used as a factual reference without copying whole manuals into this project.

## Revision 3 development-only fixture tooling

The native Swift runtime still adds no third-party package dependency. Fixture
regeneration uses externally installed ReportLab 4.4.9, pypdf 5.9.0, Pillow 12.3.0
and charset-normalizer 3.4.7, pinned in `tools/fixtures/requirements.txt`. ReportLab
generates ordinary vector barcode geometry; this repository does not vendor its
implementation, library assets or font files. pypdf adjusts the original synthetic
page dictionaries. Pillow creates analytic checker images. These tools and any
transitive dependencies keep their own licenses; none is shipped in the Mac app.

Source/provenance entry points: https://docs.reportlab.com/ ;
https://github.com/py-pdf/pypdf ; https://github.com/python-pillow/Pillow ;
https://github.com/jawah/charset_normalizer . Exact versions above identify the
preparation environment, not latest-version endorsements.

Optional source validation uses external Poppler `pdftoppm`, pyzbar 0.1.9 and
ZBar. Their libraries/binaries are not redistributed. Source projects:
https://poppler.freedesktop.org/ ; https://github.com/NaturalHistoryMuseum/pyzbar ;
https://github.com/mchehab/zbar . Ordinary CI does not install or invoke them.

## Verified direct development dependency inventory — 2026-09-17

These are existing dependencies, not newly installed tools or version updates.
Exact published-version metadata was inspected for the four fixture pins.
No package source, library assets, fonts, manuals or dependency binaries were
added to the repository or app. Project code does not modify these packages.

| Component/version | License identification | Purpose and delivery | Primary evidence |
|---|---|---|---|
| ReportLab 4.4.9 | BSD-3-Clause, mapped from the three conditions in the exact sdist license.txt | Development-only synthetic vector/barcode generation; external package, not bundled | [Exact metadata](https://pypi.org/pypi/reportlab/4.4.9/json) |
| pypdf 5.9.0 | BSD-3-Clause, declared license expression | Development-only synthetic PDF dictionaries/rotation; external package, not bundled | [Exact metadata](https://pypi.org/pypi/pypdf/5.9.0/json) |
| Pillow 12.3.0 | MIT-CMU, declared license expression | Development-only analytic fixture images; external package, not bundled | [Exact metadata](https://pypi.org/pypi/Pillow/12.3.0/json) |
| charset-normalizer 3.4.7 | MIT, declared license metadata | Pinned fixture preparation dependency; external package, not bundled | [Exact metadata](https://pypi.org/pypi/charset-normalizer/3.4.7/json) |
| actions/checkout at 3d3c42e5aac5ba805825da76410c181273ba90b1 | MIT, exact commit license inspected | CI-only checkout; not bundled in products | [Pinned license](https://raw.githubusercontent.com/actions/checkout/3d3c42e5aac5ba805825da76410c181273ba90b1/LICENSE) |
| actions/upload-artifact at 043fb46d1a93c77aae656e7c1c64a875d1fc6a0a | MIT, exact commit license inspected | CI-only artifact handling; not bundled in products | [Pinned license](https://raw.githubusercontent.com/actions/upload-artifact/043fb46d1a93c77aae656e7c1c64a875d1fc6a0a/LICENSE) |

Pillow's exact current pin declares MIT-CMU; do not substitute an older HPND
identifier from historical Pillow material. ReportLab's metadata says BSD
without an SPDX expression; the BSD-3-Clause identification above is the
inspection mapping, not a claim that the publisher declared that expression.
The exact sdist checksum was verified before reading only its license member:
`7cf487764294ee791a4781f5a157bebce262a666ae4bbb87786760a9676c9378`.
Both pinned action license files have SHA256
`3e855ffa704114a51628ef8f0bf3aeb41728adf9d9070e263bf58aa5640b0eb5`.

Swift manifests have no remote package dependency; LabelMac's package dependency
is the local LabelCore package. The application uses OS-supplied Apple frameworks
and Swift/system runtimes. CUPS ABI integration calls the OS-supplied library
through independently authored adapters and existing public API provenance;
no CUPS implementation or proprietary driver is bundled. SDK/toolchain/OS versions
are captured per validation receipt rather than inferred from these source pins.

This direct inventory does not complete the release provenance gate. External
tool/action transitive components, exact optional Poppler/ZBar installation
versions/licenses, artifact-level redistribution obligations, complete source
provenance and future installer/adapter dependencies still require review before
distribution. Preserve external license notices if a dependency is later bundled;
the repository MIT license does not replace them. No legal clean-room or complete
license-compliance determination is claimed.

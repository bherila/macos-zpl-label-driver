# Third-party notices and provenance

No third-party runtime source is vendored in this starter scaffold. Apple SDK frameworks are system dependencies, not relicensed by this repository. GitHub Actions are development dependencies referenced by immutable commits. The Swift toolchain is externally supplied.

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

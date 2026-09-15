# Revision 3 preparation validation

Prepared on 2026-09-15 in Linux x86_64, Swift 6.2.1, Python 3.13.5.
No Mac, physical printer, system queue or GitHub runner was used.

## Checks performed on the final extension

| Check | Result | What it establishes |
|---|---|---|
| Portable Swift debug | 47 XCTest methods, zero failures | Existing 8 layout tests plus 39 tests of new packing, graphics, order and option code |
| Portable Swift release | The same 47 methods, zero failures | Optimized build of portable logic, not Apple execution |
| Python regression suite | 34 methods, zero failures | Existing 20 checks plus strict decoder negatives and fixture metadata/integrity |
| Independent bitmap round-trip | 132 cases in each build configuration | Swift PBM, Swift ZPL, Python decoder and Python analytic pixel oracle agree |
| Lab non-overwrite guard | Existing vector-directory request refused | Developer CLI does not clobber an existing destination |
| Inert backend ABI harness | 15 cases in each build configuration | File/stdin, allowlisted options, no payload/identity leakage, bad destinations, invalid values, missing/directory/symlink paths, size cap, SIGTERM and stalled-pipe deadline |
| Generated source structure | 17 PDFs / 27 pages checked with pypdf | Page counts, boxes, Rotate and UserUnit match manifest |
| Source barcodes | 62 Code128/QR symbol instances across the 27 pages matched expected payloads | Poppler whole-page rendering at nominal 500 DPI + ZBar decoding; not final-resolution/hardware proof |
| Visual fixture review | All 27 PDF pages rendered; contact sheets inspected | Readable intended layouts; rotations, shifted origins, fine-text cases and multiple-region layouts are intentional |
| PPD parser check | All 3 descriptors opened with Linux libcups; status 0 | Parser-level syntax only; `cupstestppd` was unavailable, so its full validation is NOT RUN |
| Repository preflight | Passed | Shared metadata, links, action pins, retained 90 acceptance IDs and baseline consistency |
| Workflow/platform checks | YAML parsed; Mac manifests parsed; shell syntax checked | Not an Actions run, Apple SDK compile or installed-runtime test |
| Fixture regeneration | Repeated generation matched committed byte hashes | Determinism in the documented preparation environment, not all future dependency versions |
| Archive and extension | ZIP CRC, content manifest and patch application checked | Full package integrity and revision-2-to-3 patch equivalence |

Debug and release reuse the same distinct tests; do not sum them into 94 distinct
unit-test methods or 264 distinct vector designs. Swift's separate Testing runner
may report zero because these tests use XCTest.

## Findings addressed or retained explicitly

A generated small-text fixture initially obscured part of an existing line; the
generator was corrected and the fixture regenerated. A nested Python string quoting
error in a temporary preparation script was fixed before any final source was tested.

At nominal 250-DPI whole-sheet source rendering, Code128 decoding failed for the
reduced four-up page and the UserUnit=2 page. All expected symbols decoded in the
500-DPI source check. This is **not** a reason to claim lower-resolution barcode
support; it reinforces the need to extract vectors before final rasterization.

Poppler's observed raster dimensions for the two physically equivalent UserUnit
examples differed. The fixture/source contract remains explicit; these whole-page
renders are not the application's physical sizing oracle. Test Quartz separately.

## Not performed or implied

No macOS ARM/Intel build/execution, Core Graphics implementation, signature-policy
admission, CUPS scheduler invocation, installed backend placement, print-dialog
interaction, browser execution, full PDF stream capture, driver installation,
USB delivery, physical scan, cutter/peeler behavior or public release happened.
The three HTML files were generated and inspected as source; they still need
actual browser printing. No commercial driver artifact was consulted.

The new code is a useful implementation candidate, not audited production software.
No global milestone or hardware/release scope is marked passed by this revision.
The narrow `labelprobe` sink discards content and is unsuitable for production queues.

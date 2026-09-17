# M3 — bounded offline legacy host-status observations

Additional partial M3-AC01/09/12 automated implementation on existing PR #81.
Public protocol provenance is R44; no proprietary driver or implementation is
inspected/copied. This is a pure Data decoder with no query, device, network,
file, coordinator or profile-default mutation. Current GC420d status-channel
and firmware support remain unobserved; production does not call this decoder.

## Contract and independent constraints

Missing status is unknown, not healthy, false or zero. General printer state is
not a job-specific print receipt. Support is unknown by default and explicit
unsupported/unverified states return distinct unavailable observations before
reading fields. With explicitly established support, nil/empty response remains
unavailable. A complete observed response never confirms a transmitted job.

The fixed-width legacy subset uses all three framed strings and validates their
field shape, ASCII digits, boolean flags and documented reserved constants.
Mode is an observed byte, not permission to enable finishing. Opaque third-string
data is validated and discarded; snapshots expose only typed facts, with shared
redacted descriptions and structural mirrors. Unknown grammar variants reject
rather than being guessed. Input larger than the project 64KiB cap rejects before
copying, and only the exact 82-byte subset is copied/parsed. Widths are constants
and numeric fields have at most eight digits, bounding indexing and arithmetic.

Parser support is not unit/channel authorization, authenticity or freshness.
The eventual coordinator must bind a qualified protocol to the actual immutable
unit/session and protect status/readiness within the same delivery ownership
boundary. It may not reinterpret batch/receive-buffer counts as a print receipt.
Some documented faults can suppress a reply; do not turn a timeout into readiness.
No modern Link-OS/SGD or generic GC420d support is assumed.

## Actual evidence

- Six focused `LegacyHostStatusTests`: PASS, exit0. All 81 nonempty truncated
  prefixes, duplicate/trailing frames, framing corruption, invalid ASCII/flags,
  reserved values, unknown mode code and opaque control characters reject.
- Twelve flags each map independently and the combined vector returns exactly
  their union. Explicit mode/count/RAM facts match synthetic expected values;
  observed thermal-transfer state does not enable unsupported profile controls.
- Default unknown, unsupported and supported-but-missing cases return unavailable;
  a 65537-byte response fails resource validation under supported mode. Redacted
  nested dumps expose no opaque field or snapshot fields. Zero-batch observation
  leaves a transmitted receipt intact and never authorizes replay.
- Required `bash scripts/ci-swift.sh`: PASS, exit0 within the 900-second
  bound. 89 Python / 197 Core / 273 Mac tests pass in debug/release, original132
  and compressed180 independent vectors, twelve finite benchmark CLI cases,
  15 inert ABI/14filter ABI/one discard pipeline per configuration, native builds,
  nested ad-hoc signatures, ARM/minimum26 metadata and packaged-worker equality.
- Actual local runtime: macOS27.0/26A428, arm64, Xcode27.0/27A266a, Swift6.4.
- Actual hardware/channel qualification, coordinator integration, job-specific
  receipt, installed scheduler, USB and physical labels: NOT RUN.

## Next action

Complete required gates and publish the coherent source/evidence follow-on.
Preceding hosted run35203016675 at406d6a4 remains active and is not evidence for
this later source. Cloud verdict applies only to a370e05/base77c29ff; no third
request, merge or release. The separately frozen B candidate remains unchanged.

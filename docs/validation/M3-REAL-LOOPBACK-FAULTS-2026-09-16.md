# Real loopback TCP fault evidence

Date: 2026-09-16. Evidence A, additional partial M3-AC05/09/12 coverage.
No GC420d/network-printer or installed-scheduler acceptance.

The existing Network.framework adapter and serialized timeout/cancellation
machine are unchanged. Test-only native peers add real callback/stream evidence
to the existing deterministic race tests, without supplying a printer address.
The existing bitmap/typed prepared encoder are reused for the format case; no
placeholder encoder, status parser, document or printer transport is introduced.

## Finite cases

- Backpressure: a Darwin peer binds only `127.0.0.1` on an owned ephemeral port,
  limits receive buffering, consumes exactly 64 bytes from a synthetic 16 MiB
  stream and stops reading. The 1000 ms adapter deadline must report
  `timedOutAfterSendAttempt` and `uncertain(bytesAccepted: 0)`, while the peer's
  observed prefix proves that zero reported framework bytes does not mean no
  transmission. No retry or device confirmation is manufactured.
- Mid-stream reset: after the same exact prefix, the peer requests zero-linger
  close. The adapter must report `sendFailedAfterAttempt` and uncertainty, not
  safe before-send failure or confirmation.
- Complete prepared format: a genuine non-byte-aligned packed bitmap and typed
  encoder create the stream. The peer varies requested read sizes across
  1/7/31/2/17 bytes; its complete reassembly must equal the prepared bytes, retain
  `^XA`/`^XZ` framing, and the local-only receipt retains the immutable snapshot.
- Before-send failure: a bound but non-listening loopback port remains owned
  throughout the attempted connection, rather than guessing an unused port.
  Network.framework may fail or keep waiting until the adapter deadline; both
  allowed errors must yield `failedBeforeTransmission`, never success/uncertainty.
  The initial exact-refusal assertion failed because this host reported
  `timedOutBeforeSend`; this observation is retained, not claimed as a pass.

The peer uses nonblocking/close-on-exec descriptors, one fixed 3-second accept/read
budget, at most 1 MiB of collected input and read buffers at most 4096 bytes.
Its stopped-reader release wait is at most 5 seconds; tests await peer termination.
The two preexisting Network listeners now require an explicit loopback endpoint,
not merely a loopback client connecting to an all-interface listener.
No server sends application bytes, scans addresses, or parses printer status.
Public Apple API provenance is [R38](../REFERENCES.md#r38); the Darwin helper is
test-only system interoperability, not a newly bundled third-party implementation.

## Observed validation

PASS: before offline accelerator, exit 0, including 132 independent round trips,
15 backend ABI, 10 filter ABI and one inert discard pipeline case.
PASS: focused 12 native TCP tests, exit 0; both observed-prefix fault cases and
complete variable-read reassembly passed. PASS: final descriptor-hygiene repeat,
12 native tests, exit 0. Parent PR #69's crop/media correction `c0619e4` is now
inherited; combined focused/full validation is pending. This work is preserved
locally, not published as ready. Parent corrected full local gate at `68264a6`
passed 67 Python/178 Core/253 Mac debug/release plus independent/inert/signature/
packaged checks. Corrected hosted 35109064959 and second review are live.
Native host: macOS 26.6.2 build 25G83,
Apple Silicon, Swift 6.3.3.

## Boundaries / next action

M3-AC05 remains open: these observations strengthen one raw-TCP adapter, but do
not qualify every network fault/status/framing policy or a production queue path.
Network.framework owns segmentation; variable receiver read sizes are not
application-visible sender short-write counts. Portable bounded-delivery tests
cover explicit short writes separately. Complete accepted-job/raw-TCP delivery,
installed scheduler exit/retry mapping, actual device confirmation, USB lifetime,
printer/network permissions and physical output remain NOT RUN. No queues,
scheduler jobs, device commands, clipboard changes, GUI launches or releases.
The maintainer's pinned Finder-only editor check is unchanged.

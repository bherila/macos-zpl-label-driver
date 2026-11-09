# Hosted queue spike: runner facts, filter/backend timing and uninstall residue — 2026-11-09

Diagnostic, run under decisions D15, D17 and D19 in [DECISIONS.md](../DECISIONS.md). **It qualifies
no acceptance criterion** and sent nothing to any printer. Every run used a throwaway GitHub-hosted
`macos-26-arm64` VM, and the queue's device was the built-in `socket` backend pointed at a loopback
listener on the same VM.

| Run | Script at | Result |
|---|---|---|
| 42695323820 | `1e61bfa` (`main` after #169) | spike completed; snapshot DIFFERS, part of it a measurement artifact |
| 42695818083 | `2b67bb8` | waits for cupsd to flush; snapshot DIFFERS, real residue identified |
| 42696301980 | `75d1b0d` | keeps non-comment file text; residue explained |

The job exits 1 on any snapshot difference by design, so all three show as failed runs. The
artifacts expire after three days; the facts below are transcribed from them.

## 1. Runner facts (identical in all three runs)

| Fact | Observed |
|---|---|
| OS | macOS 26.7.2 (25G332), image `macos-26-arm64` 20261102.0473 |
| CPU | `Apple M1 (Virtual)`, `arm64` |
| **SIP** | **disabled** (`csrutil status`) |
| Gatekeeper | assessments enabled |
| `sudo -n` | works, no password |
| Scheduler | running, local socket `/private/var/run/cupsd`, CUPS 2.3.4, no destinations |
| CUPS settings | sharing, remote admin and web interface off (`cupsctl`, read only, unchanged) |
| Built-in backends | include `usb` and `socket`, both `r-xr-xr-x root:wheel` |
| `lpadmin` with a PPD | works, warns *"Printer drivers are deprecated and will stop working in a future version of CUPS"* |

Consequences:
- **`M1-AC01` cannot pass on this surface.** It requires the real scheduler to run the filter
  "without … an altered security policy", and SIP is off.
- **The runner cannot answer whether SIP would refuse a product backend** in
  `/usr/libexec/cups/backend`, because SIP is off. That needs a retail-configured Mac.
- The PPD-driver deprecation warning is a long-term risk to the CUPS/PPD path (D09). It is
  recorded here, not decided here.

## 2. D17: a lock held by the filter does not cover delivery

The spike filter emits 16 MiB, and the listener reads at 512 KiB/s.

| Run | Filter ran | Last byte after filter exit |
|---|---:|---:|
| 42695323820 | 75 s | **4 s** |
| 42695818083 | 76 s | **4 s** |
| 42696301980 | 75 s | **4 s** |

The filter's writes were held back by the pipe for almost the whole transfer. The gap is the data
still sitting in the pipe and socket buffers when it exited, about 2 MiB at this rate. That gap is
positive every time, so **a lock held only by the filter is released while the backend is still
delivering**. On a real printer the size of the gap depends on buffer sizes and device speed. It
never reaches zero, and the printer's own buffer is a further, separate stage.

D17 cannot stand as written. The options need a maintainer decision.

## 3. D19: what uninstall leaves behind

The uninstall was `lpadmin -x` followed by removing the spike's files under `/Library/Printers`.

- **Lazy write.** cupsd had rewritten `printers.conf` 28 s and 27 s after `lpadmin -x` (runs 2 and 3, polled every 2 s). A snapshot taken
  sooner sees the pre-removal file. The first run's diff was partly this artifact.
- **`printers.conf`** then differs from its empty baseline only by `NextPrinterId 2`, cupsd's queue-ID
  counter. This is harmless scheduler bookkeeping that any add and remove leaves.
- **`printers.conf.O`, cupsd's own backup, keeps the removed queue's whole definition**: name, UUID,
  make and model, **`DeviceURI`**, state and policies. The spike's URI was `socket://127.0.0.1:9100`.
  A product queue's `usb://` URI usually carries the printer's serial number, which `AGENTS.md`
  forbids exposing. The backup is overwritten at cupsd's next configuration write. It is not
  removed.
- Everything else recorded matched the baseline: `lpstat -v` and `-d`, `pkgutil --pkgs`, the
  `/Library/Printers` tree, `cupsd.conf`, `cups-files.conf` and `snmp.conf`.
- Not recorded: the job history and spool, which keep the job by design.

So an uninstall verified by this snapshot can **never** be literally byte-clean at the scheduler
layer. D19's rule, "equal to the baseline", needs a stated allowance for scheduler bookkeeping and a
decision on the `.O` backup.

## Not shown

Real USB delivery, the GC420d, a retail Mac with SIP on, installation by `.pkg`, restart behaviour,
and the product filter. All remain NOT RUN.

#!/usr/bin/env bash
# Hosted-runner queue spike (DECISIONS.md D15, D17, D19). Throwaway, diagnostic only.
#
# Runs ONLY on a GitHub-hosted macOS runner, a VM destroyed after the job. It never touches a
# printer: the queue's device is the built-in socket backend pointed at a loopback listener on
# this VM, which reads slowly on purpose and discards what it receives.
#
#   1. records runner facts (OS, SIP, Gatekeeper, sudo, scheduler, protected CUPS paths);
#   2. snapshots the CUPS/package/filesystem state an install could touch;
#   3. installs a throwaway filter, PPD and queue under /Library/Printers;
#   4. prints one job and records when the filter exits versus when the backend's last byte
#      reaches the listener, which is the open question in D17 (does a lock held by the filter
#      cover device delivery?);
#   5. uninstalls, snapshots again and diffs against the baseline (D19).
#
# It is not a product installer and its success qualifies no acceptance criterion.
set -uo pipefail
export LC_ALL=C

readonly queue='LabelPrinterDriver_SPIKE'
readonly root='/Library/Printers/LabelPrinterDriver-Spike'
readonly filter="$root/spike-filter"
readonly ppd_name='spike.ppd'
readonly port=9100
readonly payload_mib=16
readonly read_bytes_per_second=$((512 * 1024))

out="${1:?usage: hosted_queue_spike.sh OUTPUT_DIRECTORY}"

if [[ "${GITHUB_ACTIONS:-}" != true || "${RUNNER_ENVIRONMENT:-}" != github-hosted || "$(uname -s)" != Darwin ]]; then
  echo 'ERROR: refusing to run outside a GitHub-hosted macOS runner; this spike changes system state' >&2
  exit 2
fi

mkdir -p "$out"
summary="$out/SUMMARY.md"
: >"$summary"
note() { printf '%s\n' "$*" | tee -a "$summary"; }
run_fact() {
  local label="$1"; shift
  local value
  value="$("$@" 2>&1)"; local status=$?
  printf -- '- **%s** (exit %s):\n\n```\n%s\n```\n\n' "$label" "$status" "$value" >>"$summary"
}

listener_pid=''
installed=0
cleanup() {
  [[ -n "$listener_pid" ]] && kill "$listener_pid" 2>/dev/null
  if [[ "$installed" == 1 ]]; then
    sudo -n /usr/sbin/lpadmin -x "$queue" 2>/dev/null
    sudo -n /bin/rm -rf -- "$root"
  fi
}
trap cleanup EXIT

note '# Hosted queue spike'
note ''
note '## 1. Runner facts'
note ''
run_fact 'sw_vers' sw_vers
run_fact 'architecture' uname -m
run_fact 'CPU' sysctl -n machdep.cpu.brand_string
run_fact 'SIP (csrutil status)' csrutil status
run_fact 'Gatekeeper (spctl --status)' spctl --status
run_fact 'passwordless sudo' sudo -n /usr/bin/true
run_fact 'scheduler (lpstat -r)' lpstat -r
run_fact 'scheduler endpoint (lpstat -H)' lpstat -H
run_fact 'CUPS version' cups-config --version
run_fact 'existing destinations (lpstat -v)' lpstat -v
run_fact 'CUPS server settings (cupsctl, read-only)' cupsctl
run_fact 'protected CUPS paths (ls -ldO)' ls -ldO /usr/libexec/cups/backend /usr/libexec/cups/filter /Library/Printers
run_fact 'built-in backends' ls -l /usr/libexec/cups/backend
run_fact 'sandbox setting' sudo -n grep -i -E '^[[:space:]]*Sandboxing' /private/etc/cups/cups-files.conf

snapshot() {
  local dir="$1"
  mkdir -p "$dir"
  lpstat -v 2>&1 | sort >"$dir/lpstat-v.txt"
  lpstat -d >"$dir/lpstat-d.txt" 2>&1
  pkgutil --pkgs | sort >"$dir/pkgutil.txt"
  sudo -n find /Library/Printers -exec stat -f '%Sp %Su:%Sg %N' {} + 2>&1 | sort >"$dir/library-printers.txt"
  # printers.conf and its backup are rewritten by cupsd with a timestamp comment; compare content only.
  sudo -n find /private/etc/cups -type f 2>/dev/null | sort | while read -r file; do
    printf '%s %s\n' "$(sudo -n grep -v '^#' "$file" | shasum -a 256 | awk '{print $1}')" "$file"
  done >"$dir/etc-cups.txt"
  # Which queue names each scheduler file still mentions: hashes alone cannot say what a difference is.
  sudo -n grep -H -E '^<(Default)?Printer ' /private/etc/cups/printers.conf /private/etc/cups/printers.conf.O \
    2>/dev/null | sort >"$dir/printers-conf-queues.txt"
  # On this throwaway VM these files hold only the spike queue, so their non-comment text is safe to keep.
  for file in printers.conf printers.conf.O; do
    sudo -n grep -v '^#' "/private/etc/cups/$file" >"$dir/$file.content" 2>/dev/null || true
  done
}

# cupsd writes printers.conf lazily, so a snapshot taken right after lpadmin -x can see the
# pre-removal file. Wait, bounded, until no scheduler file names the spike queue as current.
wait_for_scheduler_flush() {
  local deadline=$(( $(date +%s) + 120 ))
  while sudo -n grep -q -E "^<(Default)?Printer ${queue}>" /private/etc/cups/printers.conf 2>/dev/null; do
    if [[ "$(date +%s)" -ge "$deadline" ]]; then
      note '- printers.conf still named the spike queue 120 s after removal.'
      return 1
    fi
    sleep 2
  done
  note "- printers.conf no longer names the spike queue ($(date +%s))."
}

note '## 2. Baseline snapshot'
note ''
snapshot "$out/before"
note "Recorded under \`before/\`: lpstat -v/-d, pkgutil --pkgs, /Library/Printers, /private/etc/cups (content hashes, comments stripped)."
note ''

note '## 3. Install a throwaway filter, PPD and queue'
note ''
work="$(mktemp -d)"
cat >"$work/spike-filter" <<EOF
#!/bin/sh
# Throwaway spike filter: ignores its input and emits ${payload_mib} MiB of zero bytes.
echo "WARNING: spike-filter start \$(date +%s) pid \$\$" >&2
/bin/dd if=/dev/zero bs=1048576 count=${payload_mib} 2>/dev/null
echo "WARNING: spike-filter end \$(date +%s) pid \$\$" >&2
exit 0
EOF
cat >"$work/$ppd_name" <<EOF
*PPD-Adobe: "4.3"
*FormatVersion: "4.3"
*FileVersion: "1.0"
*LanguageVersion: English
*LanguageEncoding: ISOLatin1
*PCFileName: "SPIKE.PPD"
*Manufacturer: "LabelPrinterDriver"
*Product: "(Spike)"
*ModelName: "LabelPrinterDriver Spike"
*ShortNickName: "LabelPrinterDriver Spike"
*NickName: "LabelPrinterDriver Spike"
*PSVersion: "(3010.000) 0"
*LanguageLevel: "3"
*ColorDevice: False
*DefaultColorSpace: Gray
*FileSystem: False
*Throughput: "1"
*LandscapeOrientation: Plus90
*TTRasterizer: Type42
*cupsVersion: 2.3
*cupsFilter2: "text/plain application/vnd.cups-raw 0 $filter"
*OpenUI *PageSize/Media Size: PickOne
*OrderDependency: 10 AnySetup *PageSize
*DefaultPageSize: w288h432
*PageSize w288h432/4x6: "<</PageSize[288 432]>>setpagedevice"
*CloseUI: *PageSize
*OpenUI *PageRegion/Media Size: PickOne
*OrderDependency: 10 AnySetup *PageRegion
*DefaultPageRegion: w288h432
*PageRegion w288h432/4x6: "<</PageSize[288 432]>>setpagedevice"
*CloseUI: *PageRegion
*DefaultImageableArea: w288h432
*ImageableArea w288h432/4x6: "0 0 288 432"
*DefaultPaperDimension: w288h432
*PaperDimension w288h432/4x6: "288 432"
EOF

if sudo -n /bin/mkdir -m 0755 "$root" &&
  sudo -n /usr/bin/install -o root -g wheel -m 0755 "$work/spike-filter" "$filter" &&
  sudo -n /usr/bin/install -o root -g wheel -m 0644 "$work/$ppd_name" "$root/$ppd_name"; then
  installed=1
  run_fact 'cupstestppd' cupstestppd "$root/$ppd_name"
  run_fact 'lpadmin create' sudo -n /usr/sbin/lpadmin -p "$queue" -E -v "socket://127.0.0.1:$port" -P "$root/$ppd_name" -o printer-is-shared=false
  run_fact 'queue readback (lpstat -v)' lpstat -v "$queue"
else
  note 'Install step FAILED; skipping the print probe.'
fi

note '## 4. D17 probe: filter exit versus backend delivery'
note ''
if [[ "$installed" == 1 ]]; then
  /usr/bin/python3 - "$port" "$read_bytes_per_second" "$out/listener.log" <<'PY' &
import socket, sys, time
port, rate, log = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
server = socket.socket()
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 16384)
server.bind(("127.0.0.1", port))
server.listen(1)
with open(log, "w") as out:
    out.write(f"listening {time.time():.3f}\n"); out.flush()
    connection, _ = server.accept()
    total, first = 0, None
    chunk = 16384
    while True:
        data = connection.recv(chunk)
        if not data:
            break
        if first is None:
            first = time.time()
            out.write(f"first-byte {first:.3f}\n"); out.flush()
        total += len(data)
        time.sleep(len(data) / rate)
    out.write(f"last-byte {time.time():.3f} total {total}\n")
PY
  listener_pid=$!
  sleep 2
  echo 'spike job: content is ignored by the spike filter' >"$work/job.txt"
  submitted="$(date +%s)"
  run_fact 'lp submit' lp -d "$queue" "$work/job.txt"
  deadline=$((submitted + 300))
  while [[ -n "$(lpstat -W not-completed -o "$queue" 2>/dev/null)" && "$(date +%s)" -lt "$deadline" ]]; do
    sleep 1
  done
  completed="$(date +%s)"
  wait "$listener_pid" 2>/dev/null
  listener_pid=''
  note "- submitted: $submitted"
  note "- job left not-completed: $completed"
  run_fact 'completed jobs' lpstat -W completed -o "$queue"
  run_fact 'listener log' cat "$out/listener.log"
  run_fact 'filter timestamps from error_log' sudo -n grep -h 'spike-filter' /private/var/log/cups/error_log
  filter_end="$(sudo -n grep -h 'spike-filter end' /private/var/log/cups/error_log | tail -1 | grep -o 'end [0-9]*' | awk '{print $2}')"
  last_byte="$(awk '/^last-byte/ {print int($2)}' "$out/listener.log")"
  if [[ -n "$filter_end" && -n "$last_byte" ]]; then
    note ''
    note "**Delivery outlived the filter by $((last_byte - filter_end)) s** (filter end $filter_end, last byte $last_byte)."
    note 'A positive gap means a lock held only by the filter is released before device delivery ends.'
  else
    note ''
    note '**Could not measure the gap**: a filter or listener timestamp is missing. See the logs above.'
  fi
  note ''
fi

note '## 5. Uninstall and compare with the baseline'
note ''
if [[ "$installed" == 1 ]]; then
  run_fact 'lpadmin remove' sudo -n /usr/sbin/lpadmin -x "$queue"
  run_fact 'remove files' sudo -n /bin/rm -rf -- "$root"
  installed=0
  removed="$(date +%s)"
  note "- removed: $removed"
  wait_for_scheduler_flush
  if sudo -n grep -q "$queue" /private/etc/cups/printers.conf.O 2>/dev/null; then
    note "- **printers.conf.O, cupsd's own backup, still names the spike queue** after uninstall."
  else
    note '- printers.conf.O does not name the spike queue.'
  fi
  note ''
fi
snapshot "$out/after"
if diff -ru "$out/before" "$out/after" >"$out/snapshot.diff"; then
  note '**Snapshot: CLEAN.** After uninstall, every recorded surface equals the baseline.'
  verdict=0
else
  note '**Snapshot: DIFFERS.** See `snapshot.diff`:'
  note ''
  note '```'
  tee -a "$summary" <"$out/snapshot.diff"
  note '```'
  verdict=1
fi
note ''
note 'Not recorded: the CUPS job history and spool, which keep the spike job by design.'
note 'This spike is diagnostic. It qualifies no acceptance criterion and sent nothing to any printer.'
exit "$verdict"

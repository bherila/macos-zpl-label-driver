#!/usr/bin/env bash
# M1 Tahoe discard-queue transaction. It is deliberately not a product installer.
set -euo pipefail
export LC_ALL=C

readonly queue='LabelProbe_DISCARDS_JOBS'
readonly uri='file:///dev/null'
readonly root='/Library/Printers/LabelPrinterDriver-M1'
readonly root_parent='/Library/Printers'
readonly filter="$root/labelcapture-filter"
readonly ownership="$root/OWNERSHIP"
readonly native_ppd_sha256='1ef382b536c71d38a8b6d02efbab8944959c538d107c084ede6519da1e8bffdb'
readonly letter_ppd_sha256='e58416fb84554546cf8f86c3f446be9e06f8c3d3f1f46f64cc40c9cd31e00d8a'
readonly a4_ppd_sha256='13ce96f08150b7a932ba3527296275aca0e1bb6092aaa6bf54a212bfd265df63'
temporary=''
scheduler=''
transaction_active=0
root_reserved=0
transaction_id=''
approved_sha=''
approved_ppd_sha=''
approved_transaction_id=''

die() { echo "ERROR: $*" >&2; exit 2; }

cleanup_temporary() {
  [[ -n "$temporary" ]] || return 0
  case "$temporary" in
    /private/tmp/label-driver-m1.??????) /bin/rm -rf -- "$temporary" ;;
    *) echo 'ERROR: refusing to remove an unexpected temporary path' >&2; return 1 ;;
  esac
}

controlled_lpstat() {
  /usr/bin/env -i LC_ALL=C PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    /usr/bin/lpstat -h "$scheduler" "$@"
}

controlled_lpadmin() {
  /usr/bin/sudo -n /usr/bin/env -i LC_ALL=C PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    /usr/sbin/lpadmin -h "$scheduler" "$@"
}

controlled_cupsdisable() {
  /usr/bin/sudo -n /usr/bin/env -i LC_ALL=C PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    /usr/sbin/cupsdisable -h "$scheduler" "$queue"
}

controlled_cupsreject() {
  /usr/bin/sudo -n /usr/bin/env -i LC_ALL=C PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    /usr/sbin/cupsreject -h "$scheduler" "$queue"
}

validate_staging_parent() {
  local metadata permissions
  [[ -d "$root_parent" && ! -L "$root_parent" ]] || die 'the fixed staging parent is not a real directory'
  metadata="$(/usr/bin/stat -f '%u:%g:%Lp:%HT' "$root_parent")" || die 'could not inspect the fixed staging parent'
  IFS=: read -r owner group permissions type <<<"$metadata"
  [[ "$owner" == 0 && "$group" == 0 && "$type" == Directory ]] || die 'the fixed staging parent is not root-owned'
  (( (8#$permissions & 8#022) == 0 )) || die 'the fixed staging parent is group- or world-writable'
}

discover_local_scheduler() {
  [[ -z "${CUPS_SERVER+x}" && -z "${IPP_PORT+x}" ]] ||
    die 'refusing CUPS_SERVER or IPP_PORT overrides for the local-only experiment'
  local observed
  observed="$(/usr/bin/env -i LC_ALL=C PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/lpstat -H)" ||
    die 'could not discover the local scheduler endpoint'
  [[ "$observed" == /* && "$observed" != *$'\n'* && -S "$observed" && ! -L "$observed" ]] ||
    die 'the observed scheduler endpoint is not a local Unix-domain socket'
  [[ "$(/usr/bin/stat -f '%u:%HT' "$observed")" == '0:Socket' ]] ||
    die 'the observed scheduler socket is not root-owned'
  if [[ -n "$scheduler" && "$scheduler" != "$observed" ]]; then
    die 'the observed local scheduler endpoint changed during the transaction'
  fi
  scheduler="$observed"
  scheduler_reachable || die 'the selected local scheduler is not reachable'
}

scheduler_reachable() {
  controlled_lpstat -r 2>/dev/null | /usr/bin/grep -Fqx 'scheduler is running'
}

# Return 0 when present, 1 when confirmed absent, and 2 when the complete local
# scheduler query failed. Callers must never reinterpret 2 as absence.
queue_state() {
  scheduler_reachable || return 2
  local inventory
  inventory="$(controlled_lpstat -p 2>/dev/null)" || return 2
  if printf '%s\n' "$inventory" | /usr/bin/grep -Eq "^printer ${queue}([[:space:]]|$)"; then
    return 0
  fi
  return 1
}

queue_uri_matches() {
  controlled_lpstat -v "$queue" 2>/dev/null | /usr/bin/grep -Fqx "device for $queue: $uri"
}

remove_queue() { controlled_lpadmin -x "$queue"; }
queue_is_default() {
  controlled_lpstat -d 2>/dev/null | /usr/bin/grep -Fqx "system default destination: $queue"
}
queue_is_disabled() {
  controlled_lpstat -p "$queue" 2>/dev/null | /usr/bin/grep -Eq "^printer ${queue} disabled([[:space:]]|$)"
}
queue_is_rejecting() {
  controlled_lpstat -a "$queue" 2>/dev/null | /usr/bin/grep -Eq "^${queue} not accepting requests since "
}

protected_root_state() {
  /usr/bin/sudo -n /usr/bin/true >/dev/null 2>&1 || return 2
  if /usr/bin/sudo -n /usr/bin/test -e "$root" || /usr/bin/sudo -n /usr/bin/test -L "$root"; then
    return 0
  fi
  return 1
}

filter_state() {
  /usr/bin/sudo -n /usr/bin/true >/dev/null 2>&1 || return 2
  if ! /usr/bin/sudo -n /usr/bin/test -e "$filter" && ! /usr/bin/sudo -n /usr/bin/test -L "$filter"; then
    return 1
  fi
  /usr/bin/sudo -n /usr/bin/test -f "$filter" &&
    ! /usr/bin/sudo -n /usr/bin/test -L "$filter" &&
    [[ "$(/usr/bin/sudo -n /usr/bin/shasum -a 256 "$filter" | /usr/bin/awk '{ print $1 }')" == "${approved_sha:-}" ]] || return 2
  return 0
}

remove_filter() { /usr/bin/sudo -n /bin/rm -f "$filter"; }
remove_ownership() { /usr/bin/sudo -n /bin/rm -f "$ownership"; }
remove_root() { /usr/bin/sudo -n /bin/rmdir "$root"; }
empty_reserved_root_matches() {
  /usr/bin/sudo -n /usr/bin/test -d "$root" &&
    ! /usr/bin/sudo -n /usr/bin/test -L "$root" &&
    [[ "$(/usr/bin/sudo -n /usr/bin/stat -f '%u:%g:%Lp' "$root")" == '0:0:755' ]] &&
    [[ -z "$(/usr/bin/sudo -n /usr/bin/find "$root" -mindepth 1 -maxdepth 1 -print -quit)" ]]
}
filter_is_absent() {
  /usr/bin/sudo -n /usr/bin/true >/dev/null 2>&1 &&
    ! /usr/bin/sudo -n /usr/bin/test -e "$filter" &&
    ! /usr/bin/sudo -n /usr/bin/test -L "$filter"
}

report_residual_state() {
  echo "RESIDUAL: inspect $root and queue $queue on scheduler $scheduler; automatic cleanup stopped." >&2
}

# Recovery is deliberately queue-first. The filter and durable ownership record
# remain until the queue is confirmed absent, preserving both behavior and the
# exact evidence needed for a finite manual recovery.
cleanup_owned_artifacts() {
  local mode="${1:-automatic}" state root_state
  [[ "$mode" == automatic || "$mode" == recovery ]] || return 1
  set +e
  if [[ "$mode" == automatic && "$root_reserved" != 1 ]]; then
    return 0
  fi
  protected_root_state
  root_state=$?
  if [[ "$root_state" == 1 ]]; then return 0; fi
  if [[ "$root_state" != 0 ]]; then
    echo 'WARNING: administrator authorization is unavailable; protected state was retained' >&2
    report_residual_state
    return 1
  fi
  if { [[ "$mode" == automatic ]] && ! ownership_record_matches_current; } ||
    { [[ "$mode" == recovery ]] && ! ownership_record_matches; }; then
    if [[ "$root_reserved" == 1 ]] && empty_reserved_root_matches && remove_root; then
      root_reserved=0
      return 0
    fi
    echo 'WARNING: retained unexpected protected ownership state during recovery' >&2
    report_residual_state
    return 1
  fi
  queue_state
  state=$?
  case "$state" in
    0)
      # lpadmin -p is create-or-modify, not create-exclusive. Even after an
      # absence check and exact URI readback, automatic rollback cannot prove
      # that this invocation acquired the queue namespace rather than racing
      # with and modifying another administrator's queue. Only explicit
      # recovery may remove a queue after validating the durable record.
      if [[ "$mode" == automatic ]]; then
        echo 'WARNING: retained an ambiguously owned queue and all recovery artifacts' >&2
        report_residual_state
        return 1
      fi
      if ! queue_uri_matches; then
        echo 'WARNING: retained altered queue and all recovery artifacts' >&2
        report_residual_state
        return 1
      fi
      if ! remove_queue; then
        echo 'WARNING: queue removal failed; retained filter and ownership record' >&2
        report_residual_state
        return 1
      fi
      queue_state
      state=$?
      if [[ "$state" != 1 ]]; then
        echo 'WARNING: queue absence could not be verified; retained recovery artifacts' >&2
        report_residual_state
        return 1
      fi
      ;;
    1) ;;
    *)
      echo 'WARNING: scheduler query failed; retained all recovery artifacts' >&2
      report_residual_state
      return 1
      ;;
  esac

  filter_state
  state=$?
  case "$state" in
    0) remove_filter || { report_residual_state; return 1; } ;;
    1) ;;
    *)
      echo 'WARNING: retained altered filter and ownership record' >&2
      report_residual_state
      return 1
      ;;
  esac
  if ! filter_is_absent; then
    echo 'WARNING: filter removal could not be verified' >&2
    report_residual_state
    return 1
  fi
  remove_ownership || { report_residual_state; return 1; }
  remove_root || { report_residual_state; return 1; }
  return 0
}

finish_process() {
  local status=$?
  trap - EXIT INT TERM HUP
  if [[ "$transaction_active" == 1 ]]; then
    cleanup_owned_artifacts automatic || status=2
  fi
  cleanup_temporary || status=2
  exit "$status"
}

interrupt_process() {
  case "$1" in
    INT) exit 130 ;;
    TERM) exit 143 ;;
    HUP) exit 129 ;;
  esac
}

transaction_checkpoint() { return 0; }
create_root() { /usr/bin/sudo -n /bin/mkdir -m 0755 "$root"; }
install_intent() { /usr/bin/sudo -n /usr/bin/install -o root -g wheel -m 0644 "$1" "$ownership"; }
install_filter() { /usr/bin/sudo -n /usr/bin/install -o root -g wheel -m 0755 "$1" "$filter"; }
validate_installed_filter() { verify_local_adhoc_arm64 "$filter" && filter_state; }
validate_installed_ppd() { /usr/bin/sudo -n /usr/bin/cupstestppd -q "$1"; }
create_queue() { controlled_lpadmin -p "$queue" -v "$uri" -i "$1" -o printer-is-shared=false; }
disable_queue() { controlled_cupsdisable; }
reject_queue() { controlled_cupsreject; }

reserve_root() {
  local reservation_signal='' status
  trap 'reservation_signal=INT' INT
  trap 'reservation_signal=TERM' TERM
  trap 'reservation_signal=HUP' HUP
  create_root
  status=$?
  if [[ "$status" == 0 ]]; then
    root_reserved=1
    transaction_active=1
  fi
  trap 'interrupt_process INT' INT
  trap 'interrupt_process TERM' TERM
  trap 'interrupt_process HUP' HUP
  if [[ -n "$reservation_signal" ]]; then
    interrupt_process "$reservation_signal"
  fi
  return "$status"
}

install_transaction() {
  local snapshot="$1" generated="$2" intent="$3"
  reserve_root || return 1
  transaction_checkpoint root-created || return 1
  install_intent "$intent" || return 1
  transaction_checkpoint intent-installed || return 1
  ownership_record_matches_current || return 1
  install_filter "$snapshot" || return 1
  transaction_checkpoint filter-installed || return 1
  validate_installed_filter || return 1
  validate_installed_ppd "$generated" || return 1
  ensure_queue_absent || return 1
  create_queue "$generated" || return 1
  queue_uri_matches || return 1
  transaction_checkpoint queue-created || return 1
  disable_queue || return 1
  transaction_checkpoint queue-disabled || return 1
  reject_queue || return 1
  transaction_checkpoint queue-rejected || return 1
  queue_uri_matches || return 1
  queue_is_disabled || return 1
  queue_is_rejecting || return 1
  ! queue_is_default || return 1
  root_reserved=0
  transaction_active=0
}

usage() {
  cat <<'EOF'
Usage:
  scripts/m1-discard-file-sink.sh --plan
  scripts/m1-discard-file-sink.sh --scheduler-preflight
  scripts/m1-discard-file-sink.sh --validate-filter FILTER_BINARY
  scripts/m1-discard-file-sink.sh --validate-ppd CANDIDATE_PPD
  scripts/m1-discard-file-sink.sh --apply FILTER_BINARY CANDIDATE_PPD
  scripts/m1-discard-file-sink.sh --remove

This is a one-off, inert Tahoe experiment. It creates only
LabelProbe_DISCARDS_JOBS, targets the built-in file:///dev/null sink, and never
sets a default destination. --apply requires an interactive OS administrator
authorization. Do not use it for a physical printer or ordinary documents.
EOF
}

validate_filter_command() {
  [[ $# -eq 1 ]] || die '--validate-filter needs FILTER_BINARY'
  local candidate="$1"
  [[ -f "$candidate" && ! -L "$candidate" && -x "$candidate" ]] || die 'filter must be an executable regular non-symlink file'
  verify_local_adhoc_arm64 "$candidate" || die 'filter is not local-ad-hoc ARM with a macOS 26.0 minimum'
  echo 'Validated local-ad-hoc ARM filter with macOS 26.0 minimum. No system state changed.'
}

validate_ppd_command() {
  [[ $# -eq 1 ]] || die '--validate-ppd needs CANDIDATE_PPD'
  validate_ppd "$1"
  echo 'Validated exact supplied experiment PPD bytes and filter declarations. No system state changed.'
}

is_supplied_ppd_sha() {
  case "$1" in
    "$native_ppd_sha256"|"$letter_ppd_sha256"|"$a4_ppd_sha256") return 0 ;;
    *) return 1 ;;
  esac
}

validate_ppd() {
  local ppd="$1" ppd_sha filter_count
  [[ -f "$ppd" && ! -L "$ppd" ]] || die 'candidate PPD must be a regular non-symlink file'
  ppd_sha="$(/usr/bin/shasum -a 256 "$ppd" | /usr/bin/awk '{ print $1 }')"
  is_supplied_ppd_sha "$ppd_sha" || die 'candidate PPD bytes do not match a supplied experiment candidate'
  /usr/bin/cupstestppd -q "$ppd" || die 'candidate PPD failed cupstestppd'
  filter_count="$(/usr/bin/awk '/^\*cupsFilter2:/{ count += 1 } END { print count + 0 }' "$ppd")"
  [[ "$filter_count" == 2 ]] || die 'candidate PPD must contain exactly two cupsFilter2 declarations'
  if /usr/bin/grep -q '^\*cupsFilter:' "$ppd"; then
    die 'candidate PPD must not contain a legacy cupsFilter declaration'
  fi
  grep -Fqx '*cupsFilter2: "application/pdf application/vnd.labelprobe 0 -"' "$ppd" || die 'candidate PPD lacks the expected PDF pass-through declaration'
  grep -Fqx '*cupsFilter2: "application/vnd.cups-pdf application/vnd.labelprobe 0 -"' "$ppd" || die 'candidate PPD lacks the expected CUPS-PDF pass-through declaration'
}

verify_local_adhoc_arm64() {
  local binary="$1" signature_info build_info
  /usr/bin/codesign --verify --strict --verbose=2 "$binary" >/dev/null 2>&1 || return 1
  signature_info="$(/usr/bin/codesign --display --verbose=4 "$binary" 2>&1)" || return 1
  printf '%s\n' "$signature_info" | /usr/bin/grep -Fqx 'Signature=adhoc' || return 1
  if printf '%s\n' "$signature_info" | /usr/bin/grep -q '^Authority='; then return 1; fi
  /usr/bin/lipo "$binary" -verify_arch arm64 >/dev/null 2>&1 || return 1
  build_info="$(/usr/bin/xcrun vtool -show-build "$binary" 2>/dev/null)" || return 1
  printf '%s\n' "$build_info" | /usr/bin/grep -Eq '^[[:space:]]+platform MACOS$' || return 1
  printf '%s\n' "$build_info" | /usr/bin/grep -Eq '^[[:space:]]+minos 26\.0$' || return 1
}

render_ppd() {
  local source="$1" destination="$2"
  /usr/bin/awk -v installed_filter="$filter" '
    /^\*cupsFilter2: / { sub(/ -"$/, " " installed_filter "\"") }
    { print }
  ' "$source" > "$destination"
  # The fixed absolute filter does not exist until the protected staging step.
  # Check every other conformance rule now and perform strict validation after
  # that exact file has been staged and signature-verified.
  /usr/bin/cupstestppd -q -W filters "$destination" || die 'generated experiment PPD failed pre-stage validation'
  grep -Fqx "*cupsFilter2: \"application/pdf application/vnd.labelprobe 0 $filter\"" "$destination" || die 'generated PDF filter declaration is not exact'
  grep -Fqx "*cupsFilter2: \"application/vnd.cups-pdf application/vnd.labelprobe 0 $filter\"" "$destination" || die 'generated CUPS-PDF filter declaration is not exact'
}

ensure_queue_absent() {
  local state
  if queue_state; then state=0; else state=$?; fi
  [[ "$state" == 1 ]] || {
    if [[ "$state" == 0 ]]; then die "refusing to replace an existing $queue queue"; fi
    die 'could not prove the experiment queue is absent from the local scheduler'
  }
}

unprivileged_root_absent() { [[ ! -e "$root" && ! -L "$root" ]]; }

ensure_not_existing() {
  ensure_queue_absent
  unprivileged_root_absent || die "refusing to replace an existing experiment root"
}

ownership_record_matches() {
  local source_ppd_sha recorded_scheduler root_metadata line_count schema_version
  /usr/bin/sudo -n /usr/bin/test -f "$ownership" &&
    ! /usr/bin/sudo -n /usr/bin/test -L "$ownership" &&
    /usr/bin/sudo -n /usr/bin/test -d "$root" &&
    ! /usr/bin/sudo -n /usr/bin/test -L "$root" || return 1
  root_metadata="$(/usr/bin/sudo -n /usr/bin/stat -f '%u:%g:%Lp' "$root")" || return 1
  [[ "$root_metadata" == '0:0:755' ]] || return 1
  line_count="$(/usr/bin/sudo -n /usr/bin/awk 'END { print NR }' "$ownership")" || return 1
  schema_version="$(/usr/bin/sudo -n /usr/bin/awk -F= '$1 == "schemaVersion" { print $2 }' "$ownership")" || return 1
  ownership_schema_is_supported "$line_count" "$schema_version" || return 1
  /usr/bin/sudo -n /usr/bin/grep -Fqx 'state=apply-intent' "$ownership" || return 1
  /usr/bin/sudo -n /usr/bin/grep -Fqx "queue=$queue" "$ownership" || return 1
  /usr/bin/sudo -n /usr/bin/grep -Fqx "uri=$uri" "$ownership" || return 1
  /usr/bin/sudo -n /usr/bin/grep -Fqx "filter=$filter" "$ownership" || return 1
  approved_sha="$(/usr/bin/sudo -n /usr/bin/awk -F= '$1 == "filterSHA256" { print $2 }' "$ownership")" || return 1
  source_ppd_sha="$(/usr/bin/sudo -n /usr/bin/awk -F= '$1 == "sourcePPDSHA256" { print $2 }' "$ownership")" || return 1
  recorded_scheduler="$(/usr/bin/sudo -n /usr/bin/awk -F= '$1 == "scheduler" { print $2 }' "$ownership")" || return 1
  approved_transaction_id=''
  if [[ "$schema_version" == 3 ]]; then
    approved_transaction_id="$(/usr/bin/sudo -n /usr/bin/awk -F= '$1 == "transactionID" { print $2 }' "$ownership")" || return 1
  fi
  [[ "$approved_sha" =~ ^[0-9a-f]{64}$ && "$source_ppd_sha" =~ ^[0-9a-f]{64}$ ]] || return 1
  if [[ "$schema_version" == 3 ]]; then
    [[ "$approved_transaction_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || return 1
  fi
  is_supplied_ppd_sha "$source_ppd_sha" || return 1
  [[ "$recorded_scheduler" == "$scheduler" ]] || return 1
}

ownership_schema_is_supported() {
  case "$1:$2" in
    8:2|9:3) return 0 ;;
    *) return 1 ;;
  esac
}

ownership_record_matches_current() {
  [[ -n "$transaction_id" ]] || return 1
  ownership_record_matches || return 1
  [[ "$approved_transaction_id" == "$transaction_id" ]]
}

plan() {
  cat <<EOF
Plan only; no system state is changed.
  queue: $queue
  sink: $uri
  staged filter: $filter
  scheduler: discovered with a controlled environment and accepted only as a root-owned local Unix socket
  PPD: byte-matched supplied candidate with only its two PDF filter program fields replaced
  recovery: retain a protected intent record; remove the exact queue only after verifying $uri and its absence afterward, then remove the exact filter, record, and empty root

Before --apply: use a locally built, ad-hoc-signed filter and a supplied candidate
PPD. The operation needs an interactive administrator approval. It does not
inspect, alter, or make default any existing destination.
Uncatchable termination can leave the protected intent record; rerun --remove
after inspecting the reported residual state. It never authorizes broader cleanup.
EOF
}

scheduler_preflight() {
  discover_local_scheduler
  validate_staging_parent
  ensure_not_existing
  echo "Validated reachable local scheduler $scheduler and absent experiment namespace. No system state changed."
}

apply() {
  [[ $# -eq 2 ]] || die '--apply needs FILTER_BINARY and CANDIDATE_PPD'
  local source_filter="$1" source_ppd="$2"
  [[ -f "$source_filter" && ! -L "$source_filter" && -x "$source_filter" ]] || die 'filter must be an executable regular non-symlink file'
  [[ -f "$source_ppd" && ! -L "$source_ppd" ]] || die 'candidate PPD must be a regular non-symlink file'
  temporary="$(/usr/bin/mktemp -d '/private/tmp/label-driver-m1.XXXXXX')"
  trap finish_process EXIT
  trap 'interrupt_process INT' INT
  trap 'interrupt_process TERM' TERM
  trap 'interrupt_process HUP' HUP
  local snapshot="$temporary/labelcapture-filter"
  local ppd_snapshot="$temporary/candidate.ppd"
  local generated="$temporary/capture.ppd"
  /bin/cp -p "$source_filter" "$snapshot"
  /bin/cp -p "$source_ppd" "$ppd_snapshot"
  [[ -f "$snapshot" && ! -L "$snapshot" && -x "$snapshot" ]] || die 'private filter snapshot is invalid'
  verify_local_adhoc_arm64 "$snapshot" || die 'filter snapshot is not local-ad-hoc ARM with a macOS 26.0 minimum'
  approved_sha="$(/usr/bin/shasum -a 256 "$snapshot" | /usr/bin/awk '{ print $1 }')"
  validate_ppd "$ppd_snapshot"
  approved_ppd_sha="$(/usr/bin/shasum -a 256 "$ppd_snapshot" | /usr/bin/awk '{ print $1 }')"
  discover_local_scheduler
  validate_staging_parent
  ensure_not_existing
  render_ppd "$ppd_snapshot" "$generated"

  # Authenticate once through the OS. The following root operations are a
  # fixed allowlist: protected staging, one named queue, and no default change.
  /usr/bin/sudo -v
  discover_local_scheduler
  validate_staging_parent
  ensure_not_existing
  transaction_id="$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')"
  [[ "$transaction_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] ||
    die 'could not create a valid transaction identifier'
  local intent="$temporary/OWNERSHIP"
  {
    echo 'schemaVersion=3'
    echo 'state=apply-intent'
    echo "transactionID=$transaction_id"
    echo "queue=$queue"
    echo "uri=$uri"
    echo "scheduler=$scheduler"
    echo "filter=$filter"
    echo "filterSHA256=$approved_sha"
    echo "sourcePPDSHA256=$approved_ppd_sha"
  } > "$intent"
  install_transaction "$snapshot" "$generated" "$intent" || die 'protected transaction failed; recovery was attempted'
  echo "Installed inert $queue. It targets $uri and is not the default printer."
}

remove() {
  discover_local_scheduler
  /usr/bin/sudo -v
  discover_local_scheduler
  ownership_record_matches || die 'refusing removal: protected transaction intent does not match'
  cleanup_owned_artifacts recovery || die 'owned experiment removal is incomplete; residual state was retained'
  echo "Removed owned inert experiment."
}

if [[ "${M1_TRANSACTION_SOURCE_ONLY:-0}" == 1 ]]; then
  return 0 2>/dev/null || exit 0
fi

case "${1:-}" in
  --plan) [[ $# -eq 1 ]] || die '--plan takes no arguments'; plan ;;
  --scheduler-preflight) [[ $# -eq 1 ]] || die '--scheduler-preflight takes no arguments'; scheduler_preflight ;;
  --validate-filter) shift; validate_filter_command "$@" ;;
  --validate-ppd) shift; validate_ppd_command "$@" ;;
  --apply) shift; apply "$@" ;;
  --remove) [[ $# -eq 1 ]] || die '--remove takes no arguments'; remove ;;
  *) usage >&2; exit 2 ;;
esac

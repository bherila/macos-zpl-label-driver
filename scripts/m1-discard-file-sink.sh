#!/usr/bin/env bash
# M1 Tahoe discard-queue transaction. It is deliberately not a product installer.
set -euo pipefail
export LC_ALL=C

readonly queue='LabelProbe_DISCARDS_JOBS'
readonly uri='file:///dev/null'
readonly root='/Library/Printers/LabelPrinterDriver-M1'
readonly filter="$root/labelcapture-filter"
readonly ownership="$root/OWNERSHIP"
readonly native_ppd_sha256='cceed46e91e0fdfe6714132085e2ffe066feedaafd33f36f430cd15ca5349ada'
readonly letter_ppd_sha256='18ef9a332ba898ea17c727303a42684f1f6c1e3eff19cd110ee34bf79023eb18'
readonly a4_ppd_sha256='4c0ba022ac562051cf9d5779c0ecfe1a4c639bb27d7ee9fca7829ef3fcdc7dac'
temporary=''

die() { echo "ERROR: $*" >&2; exit 2; }

cleanup_temporary() {
  [[ -n "$temporary" ]] || return 0
  case "$temporary" in
    /private/tmp/label-driver-m1.??????) /bin/rm -rf -- "$temporary" ;;
    *) echo 'ERROR: refusing to remove an unexpected temporary path' >&2; return 1 ;;
  esac
}

rollback_after_apply_error() {
  local status=$?
  trap - ERR
  cleanup_owned_artifacts
  exit "$status"
}

cleanup_owned_artifacts() {
  set +e
  if [[ "${queue_installed:-0}" == 1 ]]; then /usr/bin/sudo /usr/sbin/lpadmin -x "$queue"; fi
  if [[ "${filter_staged:-0}" == 1 ]]; then /usr/bin/sudo /bin/rm -f "$filter" "$ownership"; fi
  if [[ "${root_created:-0}" == 1 ]]; then /usr/bin/sudo /bin/rmdir "$root"; fi
}

fail_after_apply() {
  cleanup_owned_artifacts
  die "$*"
}

usage() {
  cat <<'EOF'
Usage:
  scripts/m1-discard-file-sink.sh --plan
  scripts/m1-discard-file-sink.sh --validate-filter FILTER_BINARY
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

validate_ppd() {
  local ppd="$1" ppd_sha filter_count
  [[ -f "$ppd" && ! -L "$ppd" ]] || die 'candidate PPD must be a regular non-symlink file'
  ppd_sha="$(/usr/bin/shasum -a 256 "$ppd" | /usr/bin/awk '{ print $1 }')"
  case "$ppd_sha" in
    "$native_ppd_sha256"|"$letter_ppd_sha256"|"$a4_ppd_sha256") ;;
    *) die 'candidate PPD bytes do not match a supplied experiment candidate' ;;
  esac
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

ensure_not_existing() {
  if /usr/bin/lpstat -p "$queue" >/dev/null 2>&1; then
    die "refusing to replace an existing $queue queue"
  fi
  [[ ! -e "$root" && ! -L "$root" ]] || die "refusing to replace an existing experiment root"
}

ownership_record_matches() {
  /usr/bin/sudo /usr/bin/test -f "$ownership" &&
    ! /usr/bin/sudo /usr/bin/test -L "$ownership" &&
    /usr/bin/sudo /usr/bin/test -f "$filter" &&
    ! /usr/bin/sudo /usr/bin/test -L "$filter" &&
    [[ "$(/usr/bin/sudo /usr/bin/awk 'END { print NR }' "$ownership")" == 6 ]] &&
    /usr/bin/sudo /usr/bin/grep -Fqx 'schemaVersion=1' "$ownership" &&
    /usr/bin/sudo /usr/bin/grep -Fqx "queue=$queue" "$ownership" &&
    /usr/bin/sudo /usr/bin/grep -Fqx "uri=$uri" "$ownership" &&
    /usr/bin/sudo /usr/bin/grep -Fqx "filter=$filter" "$ownership" &&
    /usr/bin/sudo /usr/bin/grep -Eq '^sourcePPDSHA256=[0-9a-f]{64}$' "$ownership" &&
    [[ "$(/usr/bin/sudo /usr/bin/awk -F= '$1 == "filterSHA256" { print $2 }' "$ownership")" == "$(/usr/bin/sudo /usr/bin/shasum -a 256 "$filter" | /usr/bin/awk '{ print $1 }')" ]]
}

plan() {
  cat <<EOF
Plan only; no system state is changed.
  queue: $queue
  sink: $uri
  staged filter: $filter
  PPD: byte-matched supplied candidate with only its two PDF filter program fields replaced
  rollback: remove the exact queue after verifying $uri, then remove only the two owned files and empty root

Before --apply: use a locally built, ad-hoc-signed filter and a supplied candidate
PPD. The operation needs an interactive administrator approval. It does not
inspect, alter, or make default any existing destination.
EOF
}

apply() {
  [[ $# -eq 2 ]] || die '--apply needs FILTER_BINARY and CANDIDATE_PPD'
  local source_filter="$1" source_ppd="$2"
  [[ -f "$source_filter" && ! -L "$source_filter" && -x "$source_filter" ]] || die 'filter must be an executable regular non-symlink file'
  [[ -f "$source_ppd" && ! -L "$source_ppd" ]] || die 'candidate PPD must be a regular non-symlink file'
  local root_created=0 filter_staged=0 queue_installed=0
  temporary="$(/usr/bin/mktemp -d '/private/tmp/label-driver-m1.XXXXXX')"
  trap cleanup_temporary EXIT
  local snapshot="$temporary/labelcapture-filter"
  local ppd_snapshot="$temporary/candidate.ppd"
  local generated="$temporary/capture.ppd"
  /bin/cp -p "$source_filter" "$snapshot"
  /bin/cp -p "$source_ppd" "$ppd_snapshot"
  [[ -f "$snapshot" && ! -L "$snapshot" && -x "$snapshot" ]] || die 'private filter snapshot is invalid'
  verify_local_adhoc_arm64 "$snapshot" || die 'filter snapshot is not local-ad-hoc ARM with a macOS 26.0 minimum'
  local approved_sha approved_ppd_sha
  approved_sha="$(/usr/bin/shasum -a 256 "$snapshot" | /usr/bin/awk '{ print $1 }')"
  validate_ppd "$ppd_snapshot"
  approved_ppd_sha="$(/usr/bin/shasum -a 256 "$ppd_snapshot" | /usr/bin/awk '{ print $1 }')"
  ensure_not_existing
  render_ppd "$ppd_snapshot" "$generated"

  # Authenticate once through the OS. The following root operations are a
  # fixed allowlist: protected staging, one named queue, and no default change.
  /usr/bin/sudo -v
  trap rollback_after_apply_error ERR
  /usr/bin/sudo /bin/mkdir -p "$root"
  root_created=1
  /usr/bin/sudo /usr/bin/install -o root -g wheel -m 0755 "$snapshot" "$filter"
  filter_staged=1
  verify_local_adhoc_arm64 "$filter" || fail_after_apply 'staged filter signature or platform contract is invalid'
  [[ "$(/usr/bin/sudo /usr/bin/shasum -a 256 "$filter" | /usr/bin/awk '{ print $1 }')" == "$approved_sha" ]] || fail_after_apply 'staged filter bytes do not match the approved snapshot'
  /usr/bin/sudo /usr/bin/cupstestppd -q "$generated" || fail_after_apply 'generated experiment PPD failed strict validation after staging'
  {
    echo 'schemaVersion=1'
    echo "queue=$queue"
    echo "uri=$uri"
    echo "filter=$filter"
    echo "filterSHA256=$approved_sha"
    echo "sourcePPDSHA256=$approved_ppd_sha"
  } | /usr/bin/sudo /usr/bin/tee "$ownership" >/dev/null
  /usr/bin/sudo /usr/sbin/chown root:wheel "$ownership"
  /usr/bin/sudo /bin/chmod 0644 "$ownership"
  /usr/bin/sudo /usr/sbin/lpadmin -p "$queue" -v "$uri" -i "$generated" -o printer-is-shared=false -E
  queue_installed=1
  /usr/bin/lpstat -v "$queue" | /usr/bin/grep -Fqx "device for $queue: $uri" || fail_after_apply 'queue URI readback failed'
  if /usr/bin/lpstat -d 2>/dev/null | /usr/bin/grep -Fqx "system default destination: $queue"; then
    fail_after_apply 'experiment unexpectedly became the default destination'
  fi
  trap - ERR
  echo "Installed inert $queue. It targets $uri and is not the default printer."
}

remove() {
  /usr/bin/sudo -v
  ownership_record_matches || die 'refusing removal: protected ownership record or filter hash does not match'
  if /usr/bin/lpstat -p "$queue" >/dev/null 2>&1; then
    /usr/bin/lpstat -v "$queue" | /usr/bin/grep -Fqx "device for $queue: $uri" || die 'refusing removal: named queue no longer targets the owned inert sink'
    /usr/bin/sudo /usr/sbin/lpadmin -x "$queue"
  fi
  /usr/bin/sudo /bin/rm -f "$filter" "$ownership"
  /usr/bin/sudo /bin/rmdir "$root"
  echo "Removed owned inert experiment."
}

case "${1:-}" in
  --plan) [[ $# -eq 1 ]] || die '--plan takes no arguments'; plan ;;
  --validate-filter) shift; validate_filter_command "$@" ;;
  --apply) shift; apply "$@" ;;
  --remove) [[ $# -eq 1 ]] || die '--remove takes no arguments'; remove ;;
  *) usage >&2; exit 2 ;;
esac

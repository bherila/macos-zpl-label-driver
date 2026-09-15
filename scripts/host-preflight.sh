#!/usr/bin/env bash
# Read-only build-host inspection. No printer enumeration, jobs or installation.
set -euo pipefail
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Requires macOS Tahoe 26+. Portable tests may run on Linux separately." >&2
  exit 2
fi
os_version="$(/usr/bin/sw_vers -productVersion)"
os_major="${os_version%%.*}"
if [[ ! "$os_major" =~ ^[0-9]+$ ]] || (( os_major < 26 )); then
  echo "macOS 26.0 minimum required; found $os_version." >&2
  exit 2
fi
/usr/bin/sw_vers
/usr/bin/uname -m
/usr/bin/xcodebuild -version
sdk_version="$(/usr/bin/xcrun --sdk macosx --show-sdk-version)"
sdk_major="${sdk_version%%.*}"
if [[ ! "$sdk_major" =~ ^[0-9]+$ ]] || (( sdk_major < 26 )); then
  echo "A macOS 26+ SDK is required; selected SDK is $sdk_version." >&2
  exit 2
fi
printf 'macOS SDK: %s\n' "$sdk_version"
/usr/bin/xcrun swift --version
printf 'Runner image: %s %s\n' "${ImageOS:-local}" "${ImageVersion:-unreported}"
printf 'Requested Mac deployment target: 26.0\n'
printf 'Signing mode: local-adhoc; no Apple account or signing secret required\n'
# This inspects scheduler availability, not attached printers or queued job titles.
if [[ -x /usr/bin/lpstat ]]; then
  if ! /usr/bin/lpstat -r; then
    echo "Scheduler status unavailable; record for M1. No device probe was performed." >&2
  fi
fi

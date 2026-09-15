#!/usr/bin/env bash
# Signs/runs ONLY the inert scaffold diagnostic. No privileged or printer actions.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Local signature validation requires macOS; nothing was signed." >&2
  exit 2
fi
os_version="$(/usr/bin/sw_vers -productVersion)"
os_major="${os_version%%.*}"
if [[ ! "$os_major" =~ ^[0-9]+$ ]] || (( os_major < 26 )); then
  echo "macOS 26.0 minimum required; found $os_version." >&2
  exit 2
fi
export MACOSX_DEPLOYMENT_TARGET=26.0
/usr/bin/xcrun swift build --package-path Packages/LabelMac --configuration release
bin_dir="$(/usr/bin/xcrun swift build --package-path Packages/LabelMac --configuration release --show-bin-path)"
source_binary="$bin_dir/label-driver-diagnostics"
if [[ ! -f "$source_binary" || -L "$source_binary" ]]; then
  echo "Expected a regular built diagnostic executable: $source_binary" >&2
  exit 2
fi
if [[ -L artifacts ]]; then
  echo "Refusing a symlinked artifact destination." >&2
  exit 2
fi
mkdir -p artifacts
work_dir="$(mktemp -d "$PWD/artifacts/local-adhoc.XXXXXX")"
# Keep the signed local copy for inspection, without mutating Swift build outputs.
local_binary="$work_dir/label-driver-diagnostics"
cp "$source_binary" "$local_binary"
/usr/bin/codesign --force --sign - --timestamp=none "$local_binary"
/usr/bin/codesign --verify --strict --verbose=2 "$local_binary"
signature_info="$(/usr/bin/codesign --display --verbose=4 "$local_binary" 2>&1)"
printf '%s\n' "$signature_info"
if ! printf '%s\n' "$signature_info" | grep -q '^Signature=adhoc$'; then
  echo "Expected an ad-hoc signature; refusing to label this local-adhoc." >&2
  exit 1
fi
if printf '%s\n' "$signature_info" | grep -q '^Authority='; then
  echo "Unexpected certificate authority in certificate-free signing mode." >&2
  exit 1
fi
/usr/bin/xcrun vtool -show-build "$local_binary"
"$local_binary"
printf 'Verified inert local-ad-hoc diagnostic: %s\n' "$local_binary"
printf 'This does not validate installed spooler/helper or Gatekeeper admission.\n'

#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

signing_mode="local-adhoc"
if [[ "${1:-}" == "--signing-mode" && -n "${2:-}" && -z "${3:-}" ]]; then
  signing_mode="$2"
elif [[ $# -ne 0 ]]; then
  echo "Usage: $0 [--signing-mode local-adhoc|developer-id]" >&2
  exit 2
fi
case "$signing_mode" in
  local-adhoc) ;;
  developer-id)
    echo "Developer-ID signing is not configured; refusing to fall back to local-ad-hoc signing." >&2
    exit 2
    ;;
  *)
    echo "Unsupported signing mode: $signing_mode" >&2
    exit 2
    ;;
esac

[[ "$(uname -s)" == "Darwin" ]] || { echo "macOS is required." >&2; exit 2; }
[[ "$(uname -m)" == "arm64" ]] || { echo "An Apple Silicon build host is required." >&2; exit 2; }
export MACOSX_DEPLOYMENT_TARGET=26.0
/usr/bin/xcrun swift build --package-path Packages/LabelMac --configuration release --product label-printer-setup
/usr/bin/xcrun swift build --package-path Packages/LabelMac --configuration release --product label-render-worker
bin_dir="$(/usr/bin/xcrun swift build --package-path Packages/LabelMac --configuration release --show-bin-path)"
source_binary="$bin_dir/label-printer-setup"
worker_binary="$bin_dir/label-render-worker"
[[ -f "$source_binary" && ! -L "$source_binary" ]] || { echo "Missing setup executable." >&2; exit 2; }
[[ -f "$worker_binary" && ! -L "$worker_binary" ]] || { echo "Missing render worker." >&2; exit 2; }
[[ ! -L artifacts ]] || { echo "Refusing a symlinked artifact directory." >&2; exit 2; }
mkdir -p artifacts
work_dir="$(mktemp -d "$PWD/artifacts/setup-app.XXXXXX")"
app="$work_dir/Label Printer Driver Setup.app"
mkdir -p "$app/Contents/MacOS"
cp resources/LabelPrinterSetup-Info.plist "$app/Contents/Info.plist"

# Stamp the source commit into the bundle, before codesign seals Info.plist.
#
# Every build lands in a fresh artifacts/setup-app.XXXXXX directory and nothing
# prunes or marks the newest, while Info.plist carried a hard-coded 0.1.0/1 with
# no provenance of any kind. A GUI observation therefore could not be tied to a
# commit: a defect already fixed in-tree could be re-reported from a stale
# bundle, and neither the tester nor a later reviewer had any way to tell. This
# records which source a bundle was actually built from.
build_revision="$(git rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
if [[ "$build_revision" != unknown ]] \
   && [[ -n "$(git status --porcelain --untracked-files=no 2>/dev/null)" ]]; then
  build_revision="$build_revision-modified"
fi
/usr/bin/plutil -replace CFBundleVersion -string "$build_revision" "$app/Contents/Info.plist"
/usr/bin/plutil -insert LabelBuildRevision -string "$build_revision" "$app/Contents/Info.plist"
cp "$source_binary" "$app/Contents/MacOS/label-printer-setup"
chmod 0755 "$app/Contents/MacOS/label-printer-setup"
cp "$worker_binary" "$app/Contents/MacOS/label-render-worker"
chmod 0755 "$app/Contents/MacOS/label-render-worker"

/usr/bin/codesign --force --sign - --timestamp=none "$app/Contents/MacOS/label-render-worker"
/usr/bin/codesign --verify --strict --verbose=2 "$app/Contents/MacOS/label-render-worker"
/usr/bin/codesign --force --sign - --timestamp=none "$app/Contents/MacOS/label-printer-setup"
/usr/bin/codesign --verify --strict --verbose=2 "$app/Contents/MacOS/label-printer-setup"
/usr/bin/codesign --force --sign - --timestamp=none "$app"
/usr/bin/codesign --verify --strict --verbose=2 "$app"
/usr/bin/codesign --verify --strict --verbose=2 "$app/Contents/MacOS/label-printer-setup"
signature_info="$(/usr/bin/codesign --display --verbose=4 "$app" 2>&1)"
/usr/bin/codesign --verify --strict --verbose=2 "$app/Contents/MacOS/label-render-worker"
[[ "$(/usr/bin/lipo -archs "$app/Contents/MacOS/label-render-worker")" == "arm64" ]]
/usr/bin/xcrun vtool -show-build "$app/Contents/MacOS/label-render-worker"
printf '%s\n' "$signature_info"
grep -q '^Signature=adhoc$' <<<"$signature_info"
if grep -q '^Authority=' <<<"$signature_info"; then
  echo "Unexpected certificate authority in local-ad-hoc mode." >&2
  exit 1
fi
/usr/bin/xcrun vtool -show-build "$app/Contents/MacOS/label-printer-setup"
[[ "$(/usr/bin/lipo -archs "$app/Contents/MacOS/label-printer-setup")" == "arm64" ]]
python3 scripts/check-packaged-worker.py "$app/Contents/MacOS/label-render-worker" "$worker_binary"
printf 'Built and verified local-ad-hoc app: %s\n' "$app"
printf 'Built from source revision: %s\n' "$build_revision"
printf 'This does not establish Gatekeeper, installation, scheduler, or printer acceptance.\n'

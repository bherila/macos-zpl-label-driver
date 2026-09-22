#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/host-preflight.sh
if [[ -n "${EXPECTED_ARCH:-}" && "$(uname -m)" != "$EXPECTED_ARCH" ]]; then
  echo "Unexpected native runner architecture: $(uname -m); expected $EXPECTED_ARCH" >&2
  exit 2
fi
export MACOSX_DEPLOYMENT_TARGET=26.0

# Native artifact properties are captured here and judged by
# scripts/check_native_artifacts.py, never by eye.
#
# `file` and `lipo -archs` used to stand below as bare commands. Both exit 0
# whatever they report -- `lipo -archs` says nothing different, to the shell,
# about `arm64`, `x86_64` or `arm64 x86_64` -- so a wrong architecture or a
# wrong minimum runtime reached the log and the build still went green. A
# reviewer reading the log would have caught it; CI could not.
#
# The macOS-only part is deliberately thin: these helpers capture tool output
# and nothing else. Every parsing and accept/reject rule lives in portable
# Python with unit tests in scripts/tests/test_native_artifacts.py, because
# lipo, vtool, codesign and plutil do not exist on the Linux host where the
# rules are written and reviewed.
#
# No capture below opens, enumerates or writes to a device.
capture_dir="$(mktemp -d "${TMPDIR:-/tmp}/label-native-captures.XXXXXX")"
trap 'rm -rf "$capture_dir"' EXIT

# Record the tool's own exit status inside the capture. Without this an error
# message on stderr and a real result are the same bytes to the checker, and
# "can't figure out the architecture type" contains no architecture at all.
capture_tool() {
  local destination="$1"
  shift
  local status=0
  "$@" >"$destination" 2>&1 || status=$?
  if (( status != 0 )); then
    printf 'CAPTURE-TOOL-FAILED status=%d\n' "$status" >>"$destination"
  fi
  printf -- '--- capture %s: %s\n' "$(basename "$destination")" "$*"
  cat "$destination"
}

# $1 is both the label in any failure message and the capture file name, so it
# must stay filename-safe.
assert_native_executable() {
  local name="$1" binary="$2"
  capture_tool "$capture_dir/$name.lipo" lipo -archs "$binary"
  capture_tool "$capture_dir/$name.vtool" xcrun vtool -show-build "$binary"
  python3 scripts/check_native_artifacts.py architecture "$name" "$capture_dir/$name.lipo"
  python3 scripts/check_native_artifacts.py minimum-os "$name" "$capture_dir/$name.vtool"
}

assert_adhoc_signature() {
  local name="$1" target="$2"
  capture_tool "$capture_dir/$name.codesign" /usr/bin/codesign --display --verbose=4 "$target"
  python3 scripts/check_native_artifacts.py signature "$name" "$capture_dir/$name.codesign"
}

python3 scripts/traceability_report.py >/dev/null
python3 scripts/run-accelerator-checks.py
python3 scripts/run-accelerator-checks.py --configuration release
core_bin_dir="$(xcrun swift build --package-path Packages/LabelCore --configuration release --show-bin-path)"
bash scripts/m1-discard-file-sink.sh --validate-filter "$core_bin_dir/labelcapture-filter"
xcrun swift test --package-path Packages/LabelMac
xcrun swift test --package-path Packages/LabelMac --configuration release
xcrun swift build --package-path Packages/LabelMac --configuration release
bin_dir="$(xcrun swift build --package-path Packages/LabelMac --configuration release --show-bin-path)"

# The inert Core Graphics diagnostic, run from the release binary so the
# capture is the program's own output and nothing else. It takes no arguments,
# opens no device and reaches no network; the assertion is that it says so.
capture_tool "$capture_dir/diagnostic.json" "$bin_dir/label-driver-diagnostics"
python3 scripts/check_native_artifacts.py diagnostic label-driver-diagnostics "$capture_dir/diagnostic.json"

for product in label-driver-diagnostics label-driver label-render-worker label-worker-supervision-fixture; do
  assert_native_executable "release-$product" "$bin_dir/$product"
done

bash scripts/sign-local-diagnostic.sh 2>&1 | tee "$capture_dir/sign-local-diagnostic.log"
signed_dir="$(python3 scripts/check_native_artifacts.py signed-directory "$capture_dir/sign-local-diagnostic.log")"
for product in label-driver-diagnostics label-driver label-render-worker label-worker-supervision-fixture; do
  assert_adhoc_signature "signed-$product" "$signed_dir/$product"
done

if bash scripts/build-local-app.sh --signing-mode developer-id; then
  echo "Developer-ID mode unexpectedly succeeded without configured credentials." >&2
  exit 1
fi
bash scripts/build-local-app.sh 2>&1 | tee "$capture_dir/build-local-app.log"
app_path="$(python3 scripts/check_native_artifacts.py built-app-path "$capture_dir/build-local-app.log")"
assert_native_executable app-label-printer-setup "$app_path/Contents/MacOS/label-printer-setup"
assert_native_executable app-label-render-worker "$app_path/Contents/MacOS/label-render-worker"
assert_adhoc_signature app-bundle "$app_path"
assert_adhoc_signature app-label-printer-setup "$app_path/Contents/MacOS/label-printer-setup"
assert_adhoc_signature app-label-render-worker "$app_path/Contents/MacOS/label-render-worker"
capture_tool "$capture_dir/app-info.json" /usr/bin/plutil -convert json -o - "$app_path/Contents/Info.plist"
python3 scripts/check_native_artifacts.py bundle-metadata app-bundle "$capture_dir/app-info.json"

# Wall-clock, throughput and peak memory are deliberately NOT asserted here. A
# shared hosted runner's timing is not a baseline, and a flaky required check is
# worse than no check; docs/VALIDATION-PLAN.md keeps those thresholds on a
# repeatable local reference run.
#
# A green run here is coverage a controller may later bind to an acceptance
# record. It is not a checked box, and it establishes nothing about
# installation, the scheduler, the GUI, Gatekeeper or a physical printer.
# No installation or device I/O is performed here.

#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/host-preflight.sh
if [[ -n "${EXPECTED_ARCH:-}" && "$(uname -m)" != "$EXPECTED_ARCH" ]]; then
  echo "Unexpected native runner architecture: $(uname -m); expected $EXPECTED_ARCH" >&2
  exit 2
fi
export MACOSX_DEPLOYMENT_TARGET=26.0
python3 scripts/traceability_report.py >/dev/null
python3 scripts/run-accelerator-checks.py
python3 scripts/run-accelerator-checks.py --configuration release
core_bin_dir="$(xcrun swift build --package-path Packages/LabelCore --configuration release --show-bin-path)"
bash scripts/m1-discard-file-sink.sh --validate-filter "$core_bin_dir/labelcapture-filter"
xcrun swift test --package-path Packages/LabelMac
xcrun swift test --package-path Packages/LabelMac --configuration release
xcrun swift build --package-path Packages/LabelMac --configuration release
xcrun swift run --package-path Packages/LabelMac --configuration release label-driver-diagnostics
bin_dir="$(xcrun swift build --package-path Packages/LabelMac --configuration release --show-bin-path)"
file "$bin_dir/label-driver-diagnostics"
lipo -archs "$bin_dir/label-driver-diagnostics"
file "$bin_dir/label-driver"
file "$bin_dir/label-render-worker"
lipo -archs "$bin_dir/label-driver"
lipo -archs "$bin_dir/label-render-worker"
bash scripts/sign-local-diagnostic.sh
if bash scripts/build-local-app.sh --signing-mode developer-id; then
  echo "Developer-ID mode unexpectedly succeeded without configured credentials." >&2
  exit 1
fi
bash scripts/build-local-app.sh
# No installation or device I/O is performed here.

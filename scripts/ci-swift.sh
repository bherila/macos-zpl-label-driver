#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/host-preflight.sh
if [[ -n "${EXPECTED_ARCH:-}" && "$(uname -m)" != "$EXPECTED_ARCH" ]]; then
  echo "Unexpected native runner architecture: $(uname -m); expected $EXPECTED_ARCH" >&2
  exit 2
fi
export MACOSX_DEPLOYMENT_TARGET=26.0
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
bash scripts/sign-local-diagnostic.sh
# M1–M5: add actual products/tests/signing as introduced. No installation or device I/O.

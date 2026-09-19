# CI macOS build artifact — 2026-09-19

The required `swift-macos-arm64` job already builds and verifies the local-ad-hoc setup app and
render worker. This slice packages that exact tested setup app on successful pushes to `main` and
uploads it as a short-lived GitHub Actions artifact.

The artifact is deliberately restricted to trusted `main` pushes. Pull requests still compile,
test, sign and verify the app, but do not publish a downloadable bundle. The uploaded directory
contains the zipped app, a SHA-256 checksum, and metadata identifying the source SHA, arm64
architecture, macOS 26.0 minimum, and local-ad-hoc signature mode. The metadata states that the
artifact does not establish installation, scheduler, GUI, Gatekeeper or printer qualification.

Retention is three days, matching the existing diagnostic artifact and cache policy. No signing
secret, private fixture, printer identifier or customer data is included.

Validation for the workflow change:

- `python3 scripts/check_repo.py` passed.
- `git diff --check` passed.
- The existing `scripts/build-local-app.sh` remains the sole producer and performs nested signature
  verification plus packaged-worker equality before the upload step.

Hosted validation of the new upload path requires the next successful push to `main`.

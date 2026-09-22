# Building and testing

Everything here is local and inert. **No command in this document enumerates, installs, configures or
prints to a printer, and none needs `sudo`.** If a step ever asks for an administrator password, stop.

## What runs where

| | Linux | macOS 26+ (Apple Silicon) |
|---|---|---|
| Python checks and tests | yes | yes |
| `Packages/LabelCore` build and tests | yes | yes |
| `Packages/LabelMac` build and tests | **no** | yes |
| Setup app build and local signing | no | yes |

`Packages/LabelMac` declares `platforms: [.macOS("26.0")]` and imports CryptoKit, Darwin and
CoreGraphics, so on Linux `swift build` stops at `no such module 'CryptoKit'`. That is expected, not a
broken checkout. For LabelMac work written on Linux, `swiftc -frontend -parse <file>` checks syntax only —
not types, overloads or `Sendable` — and hosted `macos-26` CI is the first real compile. Say so in the PR.

## Requirements

- **Swift 6 or newer.** CI uses the Xcode toolchain on `macos-26`; Swift 6.1 on Linux and 6.4 on macOS
  27 are both known to work.
- **Python 3.10 or newer**, standard library only. No imaging or third-party package is needed.
- **macOS:** macOS 26.0 or newer on Apple Silicon, with a macOS SDK of at least 26.0.
  `bash scripts/host-preflight.sh` checks all three and performs no device probe.
- **Linux:** the CUPS development headers, because `LabelCore` builds a small C bridge against them.
  Without them the build fails with `cups/cups.h: No such file or directory`.

  ```sh
  sudo apt-get install -y libcups2-dev     # Debian/Ubuntu; this is the only step here that uses sudo
  ```

## The checks, fastest first

Run from the repository root. This is the set `AGENTS.md` requires before a pull request.

```sh
python3 scripts/check_repo.py                    # links, metadata, action pins, workflow rules
python3 scripts/check_test_surfaces.py           # every criterion declares one execution surface
python3 -m unittest discover -s scripts/tests    # well under a minute
python3 scripts/run-accelerator-checks.py        # LabelCore tests plus the independent ZPL oracle
swift test --package-path Packages/LabelCore     # ~330 tests, a few seconds once built
# macOS only:
swift test --package-path Packages/LabelMac      # ~430 tests, about three minutes once built
```

The first `LabelMac` build takes several minutes; later runs are incremental. Test counts drift upward,
so trust the command's own summary line rather than the figures above.

### The CI-equivalent sequence (macOS)

```sh
bash scripts/ci-swift.sh
```

This is exactly what the `swift-macos-arm64` job runs, and takes about eleven minutes. In order: host
preflight; the accelerator suite in debug and release; the inert CUPS capture filter's validation;
`LabelMac` tests in debug and release; a release build; the inert Core Graphics diagnostic; architecture
checks on the built executables; local ad-hoc signing of the diagnostic; a check that Developer-ID mode
**refuses** rather than silently falling back; and finally the setup app build.

### One test, one suite

```sh
swift test --package-path Packages/LabelMac --filter WorkflowEditorTests
swift test --package-path Packages/LabelMac --filter testANoOpCommitStillRejectsAStaleEditBinding
python3 -m unittest scripts.tests.test_manifest_audit
```

## Building the setup app

```sh
bash scripts/build-local-app.sh
```

macOS on Apple Silicon only. It builds a release `label-printer-setup` and `label-render-worker`,
assembles `Label Printer Driver Setup.app`, signs it **local ad-hoc** — no Apple account, Team ID,
provisioning or notarization — verifies the signatures, and prints two lines you should keep:

```
Built and verified local-ad-hoc app: <repo>/artifacts/setup-app.XXXXXX/Label Printer Driver Setup.app
Built from source revision: 9fe4d4840a7a
```

Every build lands in a fresh `artifacts/setup-app.XXXXXX` directory, and nothing prunes old ones. The
source revision is stamped into the bundle so an observation can be tied to a commit; a `-modified`
suffix means the tree had uncommitted changes. Before reporting anything seen in the app, confirm which
build you are driving and **quit every other running copy**:

```sh
plutil -p "<app>/Contents/Info.plist" | grep -E 'CFBundleVersion|LabelBuildRevision'
```

A local ad-hoc signature is not notarization and does not establish publisher trust. Opening the app
installs nothing. `--signing-mode developer-id` deliberately fails: it is not configured, and it refuses
to fall back.

## Offline conversion and the USB probe

`label-driver convert` and `validate` turn a PDF into an offline ZPL envelope and an exact preview; see
the [README](../README.md#offline-pdf-conversion-development-only). The envelope must not be sent to a
printer.

To observe an attached printer without touching it:

```sh
ioreg -a -l -r -c IOUSBHostDevice | python3 scripts/usb_identity_probe.py
```

It reads the host I/O Registry only and never prints a serial number. Never post a serial or the
`--fingerprint` value; compare fingerprints locally and report only same or different.

## Before you commit

`MANIFEST.sha256` covers every tracked file and CI enforces it. Stage your files first — the refresh reads
the git index, so an unstaged new file is invisible to it — then:

```sh
git add <your paths>
python3 scripts/refresh_manifest.py --backfill
git add MANIFEST.sha256
python3 scripts/manifest_audit.py --enforce-covered --enforce-coverage   # must exit 0
git diff --cached --check
```

Stage explicit paths rather than `git add -A` if your worktree holds untracked personal files.

Any change outside the ledger's short list of bookkeeping paths makes existing acceptance records stale
until a following change re-seals them. That is expected; say so in the pull request. The rules are in
[AGENTS.md](../AGENTS.md) and [TRACEABILITY.md](TRACEABILITY.md).

## Two shell traps that have cost real time here

**A pipeline reports its last command's status.** `swift test | tail -3 && git commit` commits a red
suite, because the status tested is `tail`'s. Use `set -o pipefail`, or read the test command's own
status, and re-check the result of anything that matters: a merge command piped through `tail` once
reported success while the merge had been refused.

**zsh expands unquoted globs.** `grep --include=*.swift` fails with `no matches found` before `grep` runs.
Quote it: `--include='*.swift'`. In zsh the per-stage status array is lower-case `pipestatus`; upper-case
`PIPESTATUS` is bash, and in zsh it is silently empty.

## When a command cannot run

Record it as **NOT RUN**, with the reason. A Linux result does not validate Core Graphics, macOS printing,
signing, USB or the GUI. A hosted macOS result does not validate a physical printer or a clean retail
installation. Compiled, simulated, GUI-tested and physically printed are four different things, and the
project never lets one stand in for another.

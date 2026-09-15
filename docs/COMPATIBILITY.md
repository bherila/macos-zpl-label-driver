# Compatibility matrix

**No new-driver configuration is qualified yet.** Baseline inputs are known; runtime/hardware results are not.

| Configuration | State | Evidence |
|---|---|---|
| Tahoe 26.0 minimum / Apple Silicon | Confirmed target; exact local patch/build/chip to observe | User-confirmed OS major only |
| Hosted `macos-26` ARM build/test/local signature | Workflows supplied; not executed during this revision | None |
| macOS older than 26 | Out of supported scope; no test matrix | Maintainer decision |
| `macos-26-intel` | Optional manual candidate; unqualified | None |
| GC420d / USB / 4×6 pre-cut / tear-off | First qualification target | User report; documented model facts, not project H evidence |
| GC420d direct thermal | Model-documented constraint | R26/R27; no device read performed |
| Cutter for this installation | Not installed; requests must be rejected | User confirmed |
| Peeler for this installation | Tear-off workflow only; peeler inventory not separately observed | Disabled; no inferred peel support |
| Gap/web tracking, offsets, current settings | Setup confirmation required | Not inferred solely from pre-cut stock |
| Raw TCP / other physical models | Retained generic objectives, unqualified; not GC420d-local blockers | None |
| Generic cutter/peeler/thermal-transfer features | Retained broader parity scope; unqualified | No matching hardware supplied |
| Preview / Safari / Chrome / Firefox | Required normal-print/native/Letter/A4 matrix | No runtime evidence yet |
| Local ad-hoc installation/update/uninstall | Active account-free delivery target | Implementation and integration pending |
| Developer ID / notarized downloads | Deferred optional release mode | No account or credentials available |
| IPP / AirPrint | Optional independent adapter investigation | No compliance claim |

## Promoting a row

Record exact app/OS/architecture, device model/resolution/firmware, connection, media/sensing/accessories, settings/profile/template revisions, SHA and evidence. A deployment target of 26.0 is not proof all 26.x/future releases work. One current hosted runtime does not qualify an untested physical Mac or USB transport.

Preserve the existing raw-print queue: its reported success is a comparison baseline, not evidence for this project's filter/renderer/backend. See [hardware reference](hardware/GC420D.md), [release scopes](RELEASE-SCOPES.md) and [scope status](SCOPE-STATUS.json). No catalogue or accessory support is inferred from one successful GC420d test.

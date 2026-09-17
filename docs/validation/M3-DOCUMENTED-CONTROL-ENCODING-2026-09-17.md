# Offline documented controls — 2026-09-17

Additional partial M3-AC03/04/12 only. The ordinary GC420d prepared-job admission
and existing two-entry baseline encoder remain unchanged. This new immutable
protocol representation is not a persisted printer profile or advertised
installed capability. New source is not covered by the earlier two cloud passes.

`ZPLDocumentedControlEncoder` produces only a bounded typed fragment with no
transport, format envelope, graphics, copies, calibration, save, reset, firmware
or accessory actuation. Every requested kind needs explicit supported status;
unknown, missing and unsupported are unavailable. Complete input returns bytes
only after validation; a late error never returns a partial fragment. Input order
is preserved and duplicate, conflicting thermal and conflicting tracking settings
fail. Maximum11 controls and a bounded output ceiling limit work and output.

| Control | Exact mapping | Constraint/interactions |
|---|---|---|
| Print/feed/backfeed | `^PRp,s,b` | All3 required; each independently intersects explicit model choices with conservative2..12 ips subset |
| Integer absolute darkness | `^MD0` then `~SD00..30` | Relative adjustment neutralized; no fractional/model-wide claim |
| Thermal method | `^MTD` or `^MTT` | Separate command qualifications; transfer never enters baseline profile |
| Gap | `^MNY` | No auto-detect/calibration; separate support declaration |
| Black mark | `^MNM,offset` | Explicit signed offset, model range and conservative-75..283 intersection |
| Label home | `^LHx,y` | Explicit pair0..32000; affects following fields |
| Shift left | `^LSvalue` | Signed-9999..9999; distinct from home; fragment must precede first field separator |
| Label top | `^LTvalue` | Explicit model range intersects-120..120; distinct from media rest position |
| Print width | `^PWvalue` | Minimum2, explicit supplied maximum; reject rather than device clamp |
| Tear-off | `^MMT` | No cutter, peel or rewind command |

The fragment must precede all graphic fields and field separators. ^PR settings
last until reissued or power-off; ^LH and ^LS similarly retain state until
reissued or power-off. A format fragment is therefore not permission to assume
these settings reset automatically at ^XZ. ^MT/^MN/^MM changes are model/session
settings, not proven format-local settings. The encoder sends no save command.
Other setting lifetimes remain model-specific until installed qualification;
future integration must resolve every supported setting or disclose leave
unchanged and validate alternating jobs. Negative ^LT has documented mechanical
risks on some models, so supplied accepted limits must reflect the installed unit.

R45 records primary command tables, revision, hash and inspected pages. Supplied
qualification and bounds are caller declarations, not authentication, hardware
observation or a privileged authorization token. Installed integration must bind
those declarations immutably to a qualified profile. This API must not be treated
as a route around production profile validation.

Five focused tests passed: exact complete fragment and ordered arguments; every
kind missing/unknown/unsupported; independent model/protocol constraints and
extreme integers; conflicts/duplicates/size/count boundaries; exact darkness
alternation and transfer/gap mapping with ordinary baseline rejection preserved.
Original accelerator suite passed exit0. Full `bash scripts/ci-swift.sh` passed
its own exit0 with finite900second deadline:89 Python,202 Core,273 Mac tests in
debug/release; original132 and compression180 independent round-trips; twelve
benchmark CLI cases; inert ABI/pipeline checks; native products and nested local
ad-hoc signatures; ARM/minimum26 metadata and packaged-worker exact equality.
Actual local runtime is macOS27.0, not Tahoe26 integration evidence. The source
was the new uncommitted feature tree above b15f058 when tested; after commit its
publication SHA is recorded in the slice handoff. No added target escapes CI.

Remaining: feed/backfeed profile/default/private-codec/snapshot propagation;
qualified ordinary-job integration; continuous tracking/label length and
non-continuous length override policy; model-specific special speeds/offsets;
accessory mappings with real matching hardware. The current guide prints the
^LL second-argument delimiter ambiguously, so this slice does not guess it.
M3-AC03 remains unchecked, rather than claim a complete control system from an
offline fragment. State isolation and physical behavior are NOT RUN. Frozen B
candidate unchanged; no scheduler, privilege, USB or physical printer I/O.

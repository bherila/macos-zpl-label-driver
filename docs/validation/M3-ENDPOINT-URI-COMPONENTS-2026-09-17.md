# Bare TCP host admission regression

Implementation checkpoint: `8743f7ac65c0217ad795454d303020bb0d051f6f` (local unpublished). Advances endpoint validation within M3-AC12; the complete privacy/permission criterion remains unchecked because production privileged IPC and installer admission are not implemented or qualified.

RawTCPEndpoint accepted URI syntax despite requiring one bare host and a separate port. A constructor-only regression reproduced six expected invalid acceptances (own test exit 1): scheme/path slash, user-info at-sign, path slash, query, fragment and backslash. No connection or DNS operation was performed by this regression.

The constructor now rejects /, @, ?, # and backslash during its existing bounded scalar admission. Nearest independent constraints: bare DNS, IPv4, IPv6 including a scope identifier, separate port and diagnostic redaction remain preserved. The regression asserts these values survive unchanged and remain redacted. Existing UTF-8 boundary tests still exercise 253/254 bytes and a single oversized grapheme; whitespace/control and port constraints are unchanged. This is delimiter rejection, not a claim of complete DNS/IP syntax validation, successful name resolution or encrypted transport.

After the fix, RawTCPDeliveryTests executed 18 tests, zero failures, own exit 0 in debug and release. These include inert constructor/redaction checks and bounded loopback transport simulator cases. Repository preflight and all 106 Python tests passed own exit 0. Logs: /tmp/zpl-endpoint-components-before.log, /tmp/zpl-endpoint-components-debug.log, /tmp/zpl-endpoint-components-release.log and /tmp/zpl-endpoint-components-{preflight,python}.log.

Full Core/native CI-equivalent baseline, packaged signature/fidelity, GUI, scheduler/admin, USB, physical printer, minimum-runtime retail-host and release validation were NOT RUN for this slice. Older whole-source acceptance evidence, including the preceding M3-AC03 assessment, is historical after this implementation change; no ledger records were refreshed. The control mapping itself is unchanged. Frozen M1 Part B candidate remains unchanged. No private printer, device command, queue modification, privilege, merge or publication occurred.

Next: finish the automated privacy boundary audit and resolve independently implementable permission/diagnostic gaps; keep privileged integration and actual hardware evidence separate.

## Tested file hashes

Packages/LabelMac/Sources/LabelMac/RawTCPDelivery.swift: b866b71321357fce976c3d9748bcfe5a40fa79bce3685dfd3478e4760a89cb34

Packages/LabelMac/Tests/LabelMacTests/RawTCPDeliveryTests.swift: d2b391b5d23721ce7ef8fffaf737bec05428c9f51ee9eca18114b860a2fbf5e5


# Exact JSON integer token conversion

First dependency of the shared JSON integer identity repair. The codecs remain unchanged, so the defect in JSON-INTEGER-IDENTITY-INVESTIGATION-2026-09-17.md remains open. No acceptance pass is claimed.

ExactJSONInteger is internal portable Swift with no Foundation numeric conversion or new dependency. It validates JSON number-token grammar, retains coefficient digits, applies decimal/exponent shifts only when discarded digits are all zero, and converts at most 19 magnitude digits to Int. Exponents saturate relative to bounded token length without overflowing; a zero coefficient remains zero even with a huge exponent. Tokens are capped at 256 KiB before allocation. This token budget is an implementation policy to review with codec admission, not a universal JSON limit.

The nearest independent constraint is exact integer identity: fractions must never become integers because a floating-point parser rounded them. Tests cover Int.min/Int.max, beyond-2^53 identities, equivalent integral decimal/exponent forms, huge positive/negative exponents, zero, overflowing values, large fractions, malformed grammar and the exact token-byte boundary. Fractional tokens such as 9007199254740993.5 and 7.000000000000000000000000001 reject without numeric coercion.

Validation on macOS 27.0 build 26A428, ARM64, Apple Swift 6.4: focused ExactJSONIntegerTests passed 3 tests exit 0. swift test -c debug/release --package-path Packages/LabelCore each passed 287 tests exit 0. python3 scripts/run-accelerator-checks.py passed exit 0: repository/fixture integrity, 106 Python tests, portable build/tests, 132 strict bitmap round-trips, 180 compression round-trips, 12 finite CLI cases, 15 CUPS ABI cases, 14 filter ABI cases and one inert discard pipeline. The preceding accelerator receipt is the typed-region admission slice; no independent oracle changed. Linux validation is NOT RUN on this Mac; the converter imports no Apple APIs.

Next required slice: retain raw numeric tokens while traversing bounded JSON, integrate exact integer conversion at all enumerated codec sites, preserve geometry decoding and existing error/wire contracts, and reproduce the original profile failure becoming a pass. Do not ship this as the completed identity repair or silently replace the missing codec integration with these scalar tests.

No product codec, device command, profile schema, queue, privilege, GUI or physical printer path changed. No printer I/O, merge or release occurred. Older source-bound acceptance remains historical.

Packages/LabelCore/Sources/LabelCore/ExactJSONInteger.swift: 3eaff5edf22845eedc548285f59ac46dd1e720fcb172044d874f7630bce78428

Packages/LabelCore/Tests/LabelCoreTests/ExactJSONIntegerTests.swift: 715f9b4b34bf4dc8136910bcc0c1cc4ca131f1030873e9a28e267cc2a387ded9

# Bounded JSON traversal retaining numeric tokens

Second dependency of the shared integer identity repair. Product codecs are not yet integrated; the original reload/fraction defect remains open and no acceptance pass is claimed.

TokenPreservingJSON is internal and returns bounded UTF-8 object/array trees with raw numeric-token values. It never converts numbers to Double or asks JSONDecoder to truncate them. It recognizes number grammar directly and delegates isolated string escape/Unicode validation to Foundation. Booleans and null remain distinct from number tokens. Duplicate decoded keys reject, including equivalent escaped key spellings. Structural/string/delimiter checks reject malformed input, trailing data and scalar-only roots.

Bounds are explicit implementation policy: input 4 MiB, numeric token 256 KiB, nesting depth 64, and 100000 value nodes. Bytes are admitted before owned allocation. Each recursion level and value is admitted before traversal; numeric tokens are admitted before retained String creation. These policies and UTF-8 encoding admission must be reconciled with existing codec contracts before integration, including any encoding/BOM compatibility. This helper is not an authorization to narrow public profile schemas.

Focused tests passed 4 methods: nested exact revision/fraction/signed-edge tokens, quoted numeric text, booleans/null, escaped keys/quotes/backslashes and surrogate-pair Unicode, malformed number/structure/string grammar, duplicate decoded keys, invalid UTF-8 and each resource bound. swift test -c debug/release --package-path Packages/LabelCore each passed 291 tests exit 0 on ARM64 macOS 27.0 build 26A428 with Apple Swift 6.4. Linux validation is NOT RUN on this Mac. No Apple graphics API is imported.

python3 scripts/run-accelerator-checks.py exited 0: repository/fixture checks, 106 Python tests, portable tests/build, 132 strict bitmap round-trips, 180 compression round-trips, 12 finite CLI cases, 15 CUPS ABI cases, 14 filter ABI cases and one inert discard pipeline. The preceding accelerator receipt is the exact scalar integer converter. The independent bitmap oracle is unchanged.

Next required slice: integrate this token-preserving boundary and ExactJSONInteger in every enumerated identity codec, preserve floating geometry and existing schema/error behavior, account for native manifest admission, and prove the original large revision/order round trip plus fractional rejection. Internal traversal tests alone do not prove those product paths repaired.

No queue, privileged operation, device command, printer I/O, manual GUI, merge or release occurred. Older exact-source acceptance remains historical. The frozen M1 Part B and physical gates remain unchanged.

Packages/LabelCore/Sources/LabelCore/TokenPreservingJSON.swift: c2df3167f8d34586488ebdd3b7640fbd6a30822e000001d88cd90ff89ec3780f

Packages/LabelCore/Tests/LabelCoreTests/TokenPreservingJSONTests.swift: 9f7ac38ae2b29861553f52286abee7326ec315f8ce094bb8344bfc671c1faca5

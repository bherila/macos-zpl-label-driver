import Foundation

/// Internal bounded UTF-8 traversal. Numeric spellings survive until typed admission.
enum TokenPreservingJSON {
    struct Number: Equatable { let token: String }
    enum Error: Swift.Error, Equatable { case malformed, limit }
    static let maximumBytes = 4 * 1024 * 1024
    static let maximumDepth = 64
    static let maximumNodes = 100_000

    static func decode(_ data: Data) throws -> Any {
        guard data.count <= maximumBytes else { throw Error.limit }
        var parser = Parser(bytes: Array(data))
        let value = try parser.value(depth: 0)
        parser.space()
        guard parser.cursor == parser.bytes.count,
              value is [String: Any] || value is [Any] else { throw Error.malformed }
        return value
    }

    private struct Parser {
        let bytes: [UInt8]
        var cursor = 0
        var nodes = 0
        mutating func space() {
            while cursor < bytes.count, [9,10,13,32].contains(bytes[cursor]) { cursor += 1 }
        }
        mutating func take(_ byte: UInt8) -> Bool {
            space()
            guard cursor < bytes.count, bytes[cursor] == byte else { return false }
            cursor += 1; return true
        }
        mutating func value(depth: Int) throws -> Any {
            guard depth <= maximumDepth, nodes < maximumNodes else { throw Error.limit }
            nodes += 1; space()
            guard cursor < bytes.count else { throw Error.malformed }
            switch bytes[cursor] {
            case 123:
                cursor += 1
                var result: [String: Any] = [:]
                if take(125) { return result }
                repeat {
                    space()
                    let key = try string()
                    guard result[key] == nil, take(58) else { throw Error.malformed }
                    result[key] = try value(depth: depth + 1)
                    if take(125) { return result }
                    guard take(44) else { throw Error.malformed }
                } while true
            case 91:
                cursor += 1
                var result: [Any] = []
                if take(93) { return result }
                repeat {
                    result.append(try value(depth: depth + 1))
                    if take(93) { return result }
                    guard take(44) else { throw Error.malformed }
                } while true
            case 34: return try string()
            case 116: try literal([116,114,117,101]); return NSNumber(value: true)
            case 102: try literal([102,97,108,115,101]); return NSNumber(value: false)
            case 110: try literal([110,117,108,108]); return NSNull()
            default: return try number()
            }
        }
        mutating func literal(_ expected: [UInt8]) throws {
            guard bytes.count - cursor >= expected.count,
                  bytes[cursor..<(cursor + expected.count)].elementsEqual(expected) else { throw Error.malformed }
            cursor += expected.count
        }
        mutating func string() throws -> String {
            guard cursor < bytes.count, bytes[cursor] == 34 else { throw Error.malformed }
            let start = cursor; cursor += 1
            while cursor < bytes.count {
                let byte = bytes[cursor]; cursor += 1
                if byte == 34 {
                    let data = Data(bytes[start..<cursor])
                    guard let value = try? JSONSerialization.jsonObject(with: data,
                        options: .fragmentsAllowed) as? String else { throw Error.malformed }
                    return value
                }
                if byte == 92 {
                    guard cursor < bytes.count else { throw Error.malformed }
                    cursor += 1 // Foundation validates escapes and surrogate pairs.
                }
            }
            throw Error.malformed
        }
        mutating func number() throws -> Number {
            let start = cursor
            func digit(_ b: UInt8) -> Bool { (48...57).contains(b) }
            if bytes[cursor] == 45 { cursor += 1 }
            guard cursor < bytes.count else { throw Error.malformed }
            if bytes[cursor] == 48 { cursor += 1 }
            else {
                guard (49...57).contains(bytes[cursor]) else { throw Error.malformed }
                while cursor < bytes.count, digit(bytes[cursor]) { cursor += 1 }
            }
            if cursor < bytes.count, bytes[cursor] == 46 {
                cursor += 1; let first = cursor
                while cursor < bytes.count, digit(bytes[cursor]) { cursor += 1 }
                guard cursor > first else { throw Error.malformed }
            }
            if cursor < bytes.count, bytes[cursor] == 101 || bytes[cursor] == 69 {
                cursor += 1
                if cursor < bytes.count, bytes[cursor] == 43 || bytes[cursor] == 45 { cursor += 1 }
                let first = cursor
                while cursor < bytes.count, digit(bytes[cursor]) { cursor += 1 }
                guard cursor > first else { throw Error.malformed }
            }
            guard cursor - start <= ExactJSONInteger.maximumTokenBytes else { throw Error.limit }
            return Number(token: String(decoding: bytes[start..<cursor], as: UTF8.self))
        }
    }
}

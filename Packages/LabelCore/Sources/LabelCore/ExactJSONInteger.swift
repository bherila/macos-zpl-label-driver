/// Exact conversion of a JSON number token, before Foundation numeric coercion.
/// Internal until codec admission also preserves tokens. Geometry is separate.
enum ExactJSONInteger {
    static let maximumTokenBytes = 256 * 1024

    static func parse(_ token: String) -> Int? {
        guard token.utf8.prefix(maximumTokenBytes + 1).count <= maximumTokenBytes else { return nil }
        let bytes = Array(token.utf8)
        guard !bytes.isEmpty else { return nil }
        var cursor = 0
        let negative = bytes[0] == 45
        if negative { cursor += 1 }
        guard cursor < bytes.count else { return nil }
        func digit(_ value: UInt8) -> Bool { (48...57).contains(value) }
        var coefficient: [UInt8] = []
        if bytes[cursor] == 48 {
            coefficient.append(48)
            cursor += 1
            if cursor < bytes.count, digit(bytes[cursor]) { return nil }
        } else {
            guard (49...57).contains(bytes[cursor]) else { return nil }
            while cursor < bytes.count, digit(bytes[cursor]) {
                coefficient.append(bytes[cursor]); cursor += 1
            }
        }
        var fractionDigits = 0
        if cursor < bytes.count, bytes[cursor] == 46 {
            cursor += 1
            let start = cursor
            while cursor < bytes.count, digit(bytes[cursor]) {
                coefficient.append(bytes[cursor]); cursor += 1
            }
            fractionDigits = cursor - start
            guard fractionDigits > 0 else { return nil }
        }
        var exponent = 0
        if cursor < bytes.count, bytes[cursor] == 101 || bytes[cursor] == 69 {
            cursor += 1
            var exponentNegative = false
            if cursor < bytes.count, bytes[cursor] == 43 || bytes[cursor] == 45 {
                exponentNegative = bytes[cursor] == 45; cursor += 1
            }
            let start = cursor
            // Larger exponents cannot alter the nonzero Int decision. Saturate
            // relative to token length without overflowing or constructing zeros.
            let saturation = bytes.count + 32
            while cursor < bytes.count, digit(bytes[cursor]) {
                exponent = min(saturation, exponent * 10 + Int(bytes[cursor] - 48))
                cursor += 1
            }
            guard cursor > start else { return nil }
            if exponentNegative { exponent = -exponent }
        }
        guard cursor == bytes.count else { return nil }
        guard let first = coefficient.firstIndex(where: { $0 != 48 }) else { return 0 }
        var digits = Array(coefficient[first...])
        let shift = exponent - fractionDigits
        if shift < 0 {
            let removed = -shift
            guard removed < digits.count,
                  digits.suffix(removed).allSatisfy({ $0 == 48 }) else { return nil }
            digits.removeLast(removed)
        } else {
            guard shift <= 19, digits.count <= 19 - shift else { return nil }
            digits.append(contentsOf: repeatElement(UInt8(48), count: shift))
        }
        guard digits.count <= 19 else { return nil }
        if negative { digits.insert(45, at: 0) }
        return Int(String(decoding: digits, as: UTF8.self))
    }
}

/// Narrow parser for the experiment's enumerated options, NOT a replacement for
/// cupsParseOptions or a production IPP/PPD option parser. Unknown keys are omitted.
public enum ProbeOptions {
    public enum ParseError: Error, Equatable { case tooLong, malformed, invalidValue, duplicate }
    public static let choices: [String: Set<String>] = [
        "ProbeSpeed": ["Preserve", "2", "3", "4"],
        "ProbeDarkness": ["Preserve", "10", "15", "20"],
        "ProbeWorkflow": ["Native", "Letter", "A4"],
        "ProbeRotation": ["0", "90", "180", "270"],
    ]
    public static func parse(_ text: String) throws -> [String: String] {
        guard text.utf8.count <= 16_384 else { throw ParseError.tooLong }
        guard !text.contains("\n"), !text.contains("\r"), !text.contains("\0") else { throw ParseError.malformed }
        var tokens: [String] = [], token = ""
        var quote: Character?, escaped = false
        for c in text {
            if escaped { token.append(c); escaped = false; continue }
            if c == "\\" { escaped = true; continue }
            if let q = quote {
                if c == q { quote = nil } else { token.append(c) }
            } else if c == "\"" || c == "'" { quote = c
            } else if c == " " || c == "\t" {
                if !token.isEmpty { tokens.append(token); token = "" }
            } else {
                guard c != "\n", c != "\r", c != "\0" else { throw ParseError.malformed }
                token.append(c)
            }
        }
        guard !escaped, quote == nil else { throw ParseError.malformed }
        if !token.isEmpty { tokens.append(token) }
        var result: [String: String] = [:]
        for item in tokens {
            let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(pair[0])
            guard let allowed = choices[key] else { continue }
            guard pair.count == 2 else { throw ParseError.invalidValue }
            let value = String(pair[1])
            guard allowed.contains(value) else { throw ParseError.invalidValue }
            guard result[key] == nil else { throw ParseError.duplicate }
            result[key] = value
        }
        return result
    }
}

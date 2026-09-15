import CUPSOptionBridge
import LabelCore

/// CUPS parses the option wire string; the existing narrow experiment schema
/// remains responsible for rejecting duplicate or unsupported selected values.
/// This is deliberately not the public product ticket schema.
enum CUPSExperimentOptions {
    enum Error: Swift.Error { case parserDisagreement }

    static func parse(_ text: String) throws -> [String: String] {
        let strict = try ProbeOptions.parse(text)
        var cups: [String: String] = [:]
        for key in ProbeOptions.choices.keys {
            var buffer = [CChar](repeating: 0, count: 256)
            let result = text.withCString { options in
                key.withCString { name in
                    label_cups_option_value(options, name, &buffer, buffer.count)
                }
            }
            guard result >= 0 else { throw Error.parserDisagreement }
            if result == 1 {
                cups[key] = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
        }
        guard cups == strict else { throw Error.parserDisagreement }
        return cups
    }
}

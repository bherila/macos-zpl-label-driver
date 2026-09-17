import Foundation
import LabelCore

/// Integer admission precedes Foundation decoding so a fractional numeric token
/// cannot become an integer through floating-point rounding. Geometry remains
/// on the normal Double decoding path. Missing/type checks remain with Codable.
enum WorkerProtocolJSON {
    enum Message {
        case conversionTicket, renderResult, failure, layoutRequest, layoutResult
        var integerPaths: [[String]] {
            switch self {
            case .conversionTicket:
                return [["schemaVersion"], ["pageNumber"], ["conversion", "cutoff"], ["extraction", "rotation"]]
            case .renderResult:
                return ["schemaVersion", "widthDots", "heightDots", "zplBytes", "previewBytes",
                        "workerMaximumResidentBytes"].map { [$0] }
            case .failure: return [["schemaVersion"]]
            case .layoutRequest:
                return [["schemaVersion"], ["maximumPages"], ["structuralPages", "*"], ["barcodePages", "*"]]
            case .layoutResult: return [["schemaVersion"], ["pages", "*", "rotation"]]
            }
        }
    }
    enum Error: Swift.Error { case invalidInteger }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data, message: Message) throws -> T {
        try validate(data, message: message)
        return try JSONDecoder().decode(type, from: data)
    }

    static func validate(_ data: Data, message: Message) throws {
        let value = try TokenPreservingJSON.decode(data)
        for path in message.integerPaths { try validate(value, path: path[...]) }
    }

    private static func validate(_ value: Any, path: ArraySlice<String>) throws {
        guard let component = path.first else {
            if value is NSNull { return } // Codable rejects null for required fields.
            guard let number = value as? TokenPreservingJSON.Number, number.integerValue != nil else {
                throw Error.invalidInteger
            }
            return
        }
        if component == "*" {
            guard let array = value as? [Any] else { return } // Codable checks container types.
            for element in array { try validate(element, path: path.dropFirst()) }
        } else if let object = value as? [String: Any], let child = object[component] {
            try validate(child, path: path.dropFirst())
        }
    }
}

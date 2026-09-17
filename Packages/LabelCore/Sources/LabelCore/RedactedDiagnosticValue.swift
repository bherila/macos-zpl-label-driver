/// Routine descriptions and structural dumps of private identity values must
/// reveal no stored fields. Explicit typed access and private codecs remain
/// available; this is diagnostic redaction rather than an access-control API.
public protocol RedactedDiagnosticValue: CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {}

public extension RedactedDiagnosticValue {
    var description: String { "\(Self.self)(redacted)" }
    var debugDescription: String { description }
    var customMirror: Mirror {
        Mirror(self, children: EmptyCollection<Mirror.Child>(), displayStyle: .struct)
    }
}

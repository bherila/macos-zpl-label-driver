import Foundation
import LabelCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// Inert experimental CUPS backend. Never installs itself, forwards content,
// writes files, changes settings, opens a network socket or accesses a printer.
// The selected queue must say DISCARDS JOBS and use labelprobe://discard.
enum ProbeFailure: Error { case arguments, destination, input, limit, timeout, empty }
func monotonic() -> Double {
    var t = timespec()
    clock_gettime(CLOCK_MONOTONIC, &t)
    return Double(t.tv_sec) + Double(t.tv_nsec) / 1_000_000_000
}
func safeMIME(_ value: String?) -> String {
    let allowed = ["application/pdf", "application/vnd.cups-pdf", "application/postscript",
                   "application/vnd.cups-postscript", "application/vnd.cups-raster",
                   "image/pwg-raster", "image/urf", "application/vnd.labelprobe"]
    return allowed.contains(value ?? "") ? value! : "unrecognized-or-unset"
}
func run() throws {
    let args = CommandLine.arguments
    if args.count == 1 {
        print("direct labelprobe://discard \"Inert Label Probe\" \"Label Probe - DISCARDS JOBS, NO PRINTER\"")
        return
    }
    guard args.count == 6 || args.count == 7, let copies = Int(args[4]), (1...10_000).contains(copies),
          let job = Int(args[1]), job > 0 else { throw ProbeFailure.arguments }
    let env = ProcessInfo.processInfo.environment
    let uri = env["DEVICE_URI"] ?? args[0]
    guard uri == "labelprobe://discard" else { throw ProbeFailure.destination }
    let options = try ProbeOptions.parse(args[5])
    let fd: Int32
    if args.count == 7 {
        fd = open(args[6], O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw ProbeFailure.input }
    } else { fd = STDIN_FILENO }
    defer { if args.count == 7 { close(fd) } }
    var st = stat()
    guard fstat(fd, &st) == 0 else { throw ProbeFailure.input }
    let mode = st.st_mode & mode_t(S_IFMT)
    if args.count == 7 {
        guard mode == mode_t(S_IFREG) else { throw ProbeFailure.input }
    } else {
        guard mode == mode_t(S_IFREG) || mode == mode_t(S_IFIFO) else { throw ProbeFailure.input }
    }
    let maxBytes = 64 * 1024 * 1024
    // Fixed bounds: no job-controlled increase and no indefinitely waiting backend.
    let deadline = monotonic() + 10
    var buffer = [UInt8](repeating: 0, count: 8192), prefix: [UInt8] = [], count = 0
    while true {
        let remaining = deadline - monotonic()
        guard remaining > 0 else { throw ProbeFailure.timeout }
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let ready = poll(&descriptor, 1, Int32(min(remaining * 1000, 250)))
        if ready < 0 { if errno == EINTR { continue }; throw ProbeFailure.input }
        if ready == 0 { continue }
        if descriptor.revents & Int16(POLLNVAL | POLLERR) != 0 { throw ProbeFailure.input }
        let n = read(fd, &buffer, buffer.count)
        if n < 0 {
            if errno == EINTR || errno == EAGAIN { continue }
            throw ProbeFailure.input
        }
        if n == 0 { break }
        guard n <= maxBytes - count else { throw ProbeFailure.limit }
        count += n
        if prefix.count < 8 { prefix.append(contentsOf: buffer.prefix(min(n, 8 - prefix.count))) }
    }
    guard count > 0 else { throw ProbeFailure.empty }
    let detected: String
    if prefix.starts(with: Array("%PDF-".utf8)) { detected = "pdf-signature" }
    else if prefix.starts(with: Array("%!PS".utf8)) { detected = "postscript-signature" }
    else if prefix.starts(with: Array("UNIRAST".utf8)) { detected = "urf-signature" }
    else if ["RaSt", "RaS2", "RaS3", "tSaR", "2SaR", "3SaR"].contains(String(bytes: prefix.prefix(4), encoding: .ascii) ?? "") { detected = "cups-or-pwg-raster-signature" }
    else { detected = "unknown-signature" }
    let report: [String: Any] = ["schemaVersion": 1, "mode": "discard-only", "bytesObserved": count,
        "input": args.count == 7 ? "file" : "stdin", "copiesArgument": copies,
        "knownOptions": options, "detectedSignature": detected,
        "contentType": safeMIME(env["CONTENT_TYPE"]), "finalContentType": safeMIME(env["FINAL_CONTENT_TYPE"]),
        "payloadRetained": false, "physicalOutput": false]
    let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
    // No title, username, path, serial, raw option string, prefix bytes or payload.
    FileHandle.standardError.write(Data("INFO: LABEL_PROBE ".utf8) + data + Data([10]))
}
signal(SIGPIPE, SIG_IGN)
do { try run() }
catch {
    // Deliberately do not reflect error/user input; detailed payloads are private.
    FileHandle.standardError.write(Data("ERROR: Label probe rejected input, destination, options, or resource limits. No printer was accessed.\n".utf8))
    exit(1)
}

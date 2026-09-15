import Foundation
import LabelCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// An inert CUPS filter experiment. It validates the documented positional job
// ABI and streams its input unchanged to the next filter/backend. It never
// opens a device, invokes a scheduler command, or retains document bytes.
enum FilterFailure: Error { case arguments, input, limit, timeout, empty, output }

func monotonic() -> Double {
    var t = timespec()
    clock_gettime(CLOCK_MONOTONIC, &t)
    return Double(t.tv_sec) + Double(t.tv_nsec) / 1_000_000_000
}

func safeMIME(_ value: String?) -> String {
    let allowed = ["application/pdf", "application/vnd.cups-pdf", "application/postscript",
                   "application/vnd.cups-postscript", "application/vnd.cups-raster",
                   "image/pwg-raster", "image/urf"]
    return allowed.contains(value ?? "") ? value! : "unrecognized-or-unset"
}

func writeAll(_ bytes: UnsafeRawBufferPointer, deadline: Double) throws {
    var offset = 0
    while offset < bytes.count {
        let remaining = deadline - monotonic()
        guard remaining > 0 else { throw FilterFailure.timeout }
        var descriptor = pollfd(fd: STDOUT_FILENO, events: Int16(POLLOUT), revents: 0)
        let ready = poll(&descriptor, 1, Int32(min(remaining * 1000, 250)))
        if ready < 0 { if errno == EINTR { continue }; throw FilterFailure.output }
        if ready == 0 || descriptor.revents & Int16(POLLNVAL | POLLERR | POLLHUP) != 0 { throw FilterFailure.output }
        let count = write(STDOUT_FILENO, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
        if count < 0 { if errno == EINTR || errno == EAGAIN { continue }; throw FilterFailure.output }
        guard count > 0 else { throw FilterFailure.output }
        offset += count
    }
}

func run() throws {
    let args = CommandLine.arguments
    guard args.count == 6 || args.count == 7,
          let job = Int(args[1]), job > 0,
          let copies = Int(args[4]), (1...10_000).contains(copies)
    else { throw FilterFailure.arguments }
    let options = try CUPSExperimentOptions.parse(args[5])
    let fd: Int32
    if args.count == 7 {
        fd = open(args[6], O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw FilterFailure.input }
    } else { fd = STDIN_FILENO }
    defer { if args.count == 7 { close(fd) } }

    var metadata = stat()
    guard fstat(fd, &metadata) == 0 else { throw FilterFailure.input }
    let mode = metadata.st_mode & mode_t(S_IFMT)
    if args.count == 7 {
        guard mode == mode_t(S_IFREG), metadata.st_size > 0, metadata.st_size <= 64 * 1024 * 1024 else { throw FilterFailure.input }
    } else {
        guard mode == mode_t(S_IFREG) || mode == mode_t(S_IFIFO) else { throw FilterFailure.input }
    }

    let deadline = monotonic() + 10
    let maximumBytes = 64 * 1024 * 1024
    var buffer = [UInt8](repeating: 0, count: 8192)
    var count = 0
    while true {
        let remaining = deadline - monotonic()
        guard remaining > 0 else { throw FilterFailure.timeout }
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let ready = poll(&descriptor, 1, Int32(min(remaining * 1000, 250)))
        if ready < 0 { if errno == EINTR { continue }; throw FilterFailure.input }
        if ready == 0 { continue }
        if descriptor.revents & Int16(POLLNVAL | POLLERR) != 0 { throw FilterFailure.input }
        let readCount = read(fd, &buffer, buffer.count)
        if readCount < 0 { if errno == EINTR || errno == EAGAIN { continue }; throw FilterFailure.input }
        if readCount == 0 { break }
        guard readCount <= maximumBytes - count else { throw FilterFailure.limit }
        try buffer.withUnsafeBytes { raw in try writeAll(UnsafeRawBufferPointer(rebasing: raw[..<readCount]), deadline: deadline) }
        count += readCount
    }
    guard count > 0 else { throw FilterFailure.empty }
    let report: [String: Any] = [
        "schemaVersion": 1,
        "mode": "pass-through-to-inert-next-stage",
        "bytesObserved": count,
        "input": args.count == 7 ? "file" : "stdin",
        "copiesArgument": copies,
        "knownOptions": options,
        "contentType": safeMIME(ProcessInfo.processInfo.environment["CONTENT_TYPE"]),
        "finalContentType": safeMIME(ProcessInfo.processInfo.environment["FINAL_CONTENT_TYPE"]),
        "payloadRetained": false,
        "physicalOutput": false,
    ]
    let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
    FileHandle.standardError.write(Data("INFO: LABEL_CAPTURE_FILTER ".utf8) + data + Data([10]))
}

signal(SIGPIPE, SIG_IGN)
do { try run() }
catch {
    FileHandle.standardError.write(Data("ERROR: Label capture filter rejected input, options, output, or resource limits. No printer was accessed.\n".utf8))
    exit(1)
}

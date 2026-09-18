import Darwin
import Foundation
import LabelMac

/// Offline conversion only. This executable never opens a queue, transport, or
/// printer endpoint; CUPS integration has a separate, unimplemented boundary.
@main
struct LabelDriverCLI {
    private static let maximumTicketBytes = 64 * 1024

    private enum Exit: Int32 {
        case success = 0
        case usage = 64
        case input = 65
        case output = 73
        case internalError = 70
        case cancelled = 130
    }

    private enum CLIError: Error {
        case usage(String)
        case input(String)
        case output(String)
    }

    private struct Invocation {
        enum Command { case validate, convert }
        let command: Command
        let input: URL
        let ticket: URL
        let output: URL?
        let previewDirectory: URL?
        let json: Bool
    }

    static func main() {
        let invocation: Invocation
        do {
            invocation = try parse(Array(CommandLine.arguments.dropFirst()))
        } catch let error as CLIError {
            fail(error, json: Array(CommandLine.arguments.dropFirst()).contains("--json"))
        } catch {
            failInput(error, json: Array(CommandLine.arguments.dropFirst()).contains("--json"))
        }
        do {
            let source = try readInput(invocation.input)
            let ticket = try readTicketData(invocation.ticket)
            let cancellation = OfflineRenderWorkerCancellation()
            let signalSources = installCancellationSignals(cancellation)
            defer { signalSources.forEach { $0.cancel() } }
            let prepared: OfflineRenderWorkerOutput
            do {
                prepared = try OfflineRenderWorkerProcess.run(
                    originalPDF: source,
                    ticketJSON: ticket,
                    workerExecutable: try renderWorkerExecutable(),
                    cancellation: cancellation
                )
            } catch let error as OfflineRenderWorkerProcess.Error {
                failWorker(error, json: invocation.json)
            }
            switch invocation.command {
            case .validate:
                emitSuccess(invocation, prepared: prepared, wroteFiles: false)
            case .convert:
                guard let output = invocation.output, let previewDirectory = invocation.previewDirectory else {
                    throw CLIError.usage("convert requires --output and --preview-dir")
                }
                try writeOutputPair(
                    zpl: prepared.zpl,
                    output: output,
                    preview: prepared.previewPBM,
                    previewOutput: previewDirectory.appending(path: "page-0001.pbm")
                )
                emitSuccess(invocation, prepared: prepared, wroteFiles: true)
            }
        } catch let error as CLIError {
            fail(error, json: invocation.json)
        } catch {
            failInput(error, json: invocation.json)
        }
    }

    private static func parse(_ args: [String]) throws -> Invocation {
        guard let commandName = args.first else { throw CLIError.usage(usage) }
        let command: Invocation.Command
        switch commandName {
        case "validate": command = .validate
        case "convert": command = .convert
        default: throw CLIError.usage(usage)
        }
        var positionals: [String] = []
        var ticket: String?
        var output: String?
        var previewDirectory: String?
        var json = false
        var index = 1
        while index < args.count {
            switch args[index] {
            case "--job-ticket", "--output", "--preview-dir":
                guard index + 1 < args.count else { throw CLIError.usage(usage) }
                let value = args[index + 1]
                switch args[index] {
                case "--job-ticket":
                    guard ticket == nil else { throw CLIError.usage(usage) }
                    ticket = value
                case "--output":
                    guard output == nil else { throw CLIError.usage(usage) }
                    output = value
                default:
                    guard previewDirectory == nil else { throw CLIError.usage(usage) }
                    previewDirectory = value
                }
                index += 2
            case "--json":
                guard !json else { throw CLIError.usage(usage) }
                json = true
                index += 1
            default:
                guard !args[index].hasPrefix("-") else { throw CLIError.usage(usage) }
                positionals.append(args[index])
                index += 1
            }
        }
        guard positionals.count == 1, let ticket else { throw CLIError.usage(usage) }
        switch command {
        case .validate:
            guard output == nil, previewDirectory == nil else { throw CLIError.usage(usage) }
        case .convert:
            guard let output, let previewDirectory else { throw CLIError.usage(usage) }
            return Invocation(
                command: command,
                input: URL(fileURLWithPath: positionals[0]),
                ticket: URL(fileURLWithPath: ticket),
                output: URL(fileURLWithPath: output),
                previewDirectory: URL(fileURLWithPath: previewDirectory),
                json: json
            )
        }
        return Invocation(
            command: command,
            input: URL(fileURLWithPath: positionals[0]),
            ticket: URL(fileURLWithPath: ticket),
            output: nil,
            previewDirectory: nil,
            json: json
        )
    }

    private static func readInput(_ url: URL) throws -> Data {
        do { return try readBoundedRegularFile(url, maximumBytes: OfflineConversion.maximumInputBytes) }
        catch { throw CLIError.input("cannot read input PDF") }
    }

    private static func readTicketData(_ url: URL) throws -> Data {
        do { return try readBoundedRegularFile(url, maximumBytes: maximumTicketBytes) }
        catch { throw CLIError.input("cannot read job ticket") }
    }

    private static func renderWorkerExecutable() throws -> URL {
        guard let executable = Bundle.main.executableURL else {
            throw CLIError.output("render worker is unavailable")
        }
        return executable.deletingLastPathComponent().appending(path: "label-render-worker")
    }

    private static func installCancellationSignals(
        _ cancellation: OfflineRenderWorkerCancellation
    ) -> [DispatchSourceSignal] {
        [SIGINT, SIGTERM].map { number in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler { cancellation.cancel() }
            source.activate()
            return source
        }
    }

    private static func readBoundedRegularFile(_ url: URL, maximumBytes: Int) throws -> Data {
        try BoundedRegularFile.read(url, maximumBytes: maximumBytes)
    }

    private static func validateNewDestination(_ url: URL) throws {
        let path = url.standardizedFileURL.path
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent, isDirectory: &isDirectory), isDirectory.boolValue,
              FileManager.default.isWritableFile(atPath: parent) else {
            throw CLIError.output("output parent is not a writable directory")
        }
        guard !FileManager.default.fileExists(atPath: path) else {
            throw CLIError.output("refusing to overwrite existing output")
        }
    }

    private static func writeNew(_ data: Data, to url: URL) throws {
        // Foundation rejects combining .atomic with .withoutOverwriting. Stage
        // under an unguessable same-directory name, then use Darwin's exclusive
        // rename so the final path is never partial and is never replaced.
        let temporary = url.deletingLastPathComponent().appending(
            path: ".label-driver-\(UUID().uuidString).tmp"
        )
        do {
            try data.write(to: temporary, options: .withoutOverwriting)
            defer { try? FileManager.default.removeItem(at: temporary) }
            let result = temporary.path.withCString { source in
                url.path.withCString { destination in
                    renameatx_np(AT_FDCWD, source, AT_FDCWD, destination, UInt32(RENAME_EXCL))
                }
            }
            guard result == 0 else { throw CLIError.output("cannot create output") }
        } catch let error as CLIError {
            throw error
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw CLIError.output("cannot create output")
        }
    }

    /// Commits the exact preview before the printer-language bytes. If the
    /// second write fails, the owned preview is removed so a failed conversion
    /// does not leave either output. This is an offline file transaction only;
    /// it never makes a queue or transport call.
    private static func writeOutputPair(zpl: Data, output: URL, preview: Data, previewOutput: URL) throws {
        guard output.standardizedFileURL != previewOutput.standardizedFileURL else {
            throw CLIError.output("ZPL and preview destinations must be distinct")
        }
        try validateNewDestination(output)
        try validateNewDestination(previewOutput)
        try writeNew(preview, to: previewOutput)
        do {
            try writeNew(zpl, to: output)
        } catch {
            do {
                try FileManager.default.removeItem(at: previewOutput)
            } catch {
                throw CLIError.output("ZPL was not written and preview cleanup failed")
            }
            throw CLIError.output("conversion outputs were not retained")
        }
    }

    private static func emitSuccess(_ invocation: Invocation, prepared: OfflineRenderWorkerOutput, wroteFiles: Bool) {
        if invocation.json {
            let result: [String: Any] = [
                "status": "prepared",
                "widthDots": prepared.result.widthDots,
                "heightDots": prepared.result.heightDots,
                "zplBytes": prepared.zpl.count,
                "previewIsExactPackedBitmap": true,
                "renderIsolation": "subprocess",
                "renderDeadlineSeconds": Int(OfflineRenderWorkerProcess.defaultDeadlineSeconds),
                "wroteFiles": wroteFiles,
                "printerIOPerformed": false,
                "formatScope": "offline-graphics-envelope-not-state-normalized",
            ]
            let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } else {
            print("Prepared \(prepared.result.widthDots)x\(prepared.result.heightDots) dots; printer I/O was not performed.")
        }
    }

    private static func failWorker(_ error: OfflineRenderWorkerProcess.Error, json: Bool) -> Never {
        switch error {
        case .timedOut:
            emitError(code: .input, message: "render worker exceeded its deadline", json: json)
            exit(Exit.input.rawValue)
        case .cancelled:
            emitError(code: .cancelled, message: "render cancelled", json: json)
            exit(Exit.cancelled.rawValue)
        case .workerFailed:
            emitError(code: .input, message: "render worker rejected the job", json: json)
            exit(Exit.input.rawValue)
        case let .jobRejected(code):
            emitError(
                code: .input,
                message: workerFailureMessage(code),
                json: json,
                name: code.rawValue
            )
            exit(Exit.input.rawValue)
        case .outputLimitExceeded:
            emitError(code: .input, message: "render job exceeds its resource limits", json: json)
            exit(Exit.input.rawValue)
        case .invalidDeadline, .workerUnavailable, .scratchUnavailable, .invalidResult:
            emitError(code: .internalError, message: "render worker failed safely", json: json)
            exit(Exit.internalError.rawValue)
        }
    }

    private static func workerFailureMessage(_ code: OfflineRenderWorkerFailure.Code) -> String {
        switch code {
        case .layoutDetectorUnavailable: "local layout detector unavailable"
        case .jobTicketInvalid: "invalid job ticket"
        case .inputUnsupported: "unsupported or malformed PDF"
        case .inputEncrypted: "encrypted PDF is not supported"
        case .annotationsUnsupported: "PDF annotations or form fields are not supported"
        case .pageOutOfRange: "requested page is unavailable"
        case .limitExceeded: "render job exceeds its resource limits"
        case .geometryInvalid: "invalid output geometry"
        case .renderFailed: "PDF rendering failed"
        case .preparationFailed: "job preparation failed"
        }
    }

    private static func fail(_ error: CLIError, json: Bool) -> Never {
        let message: String
        let code: Exit
        switch error {
        case let .usage(value): message = value; code = .usage
        case let .input(value): message = value; code = .input
        case let .output(value): message = value; code = .output
        }
        emitError(code: code, message: message, json: json)
        exit(code.rawValue)
    }

    private static func failInput(_ error: Error, json: Bool) -> Never {
        emitError(code: .input, message: "preparation failed: \(String(describing: error))", json: json)
        exit(Exit.input.rawValue)
    }

    private static func emitError(code: Exit, message: String, json: Bool, name explicitName: String? = nil) {
        if json {
            let name: String
            if let explicitName {
                name = explicitName
            } else {
                name = switch code {
                case .usage: "USAGE"
                case .input: "INPUT_ERROR"
                case .output: "OUTPUT_ERROR"
                case .internalError: "INTERNAL_ERROR"
                case .cancelled: "CANCELLED"
                case .success: "SUCCESS"
                }
            }
            let result: [String: Any] = ["status": "error", "code": name, "message": message]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]) {
                FileHandle.standardError.write(data)
                FileHandle.standardError.write(Data("\n".utf8))
                return
            }
        }
        FileHandle.standardError.write(Data("label-driver: \(message)\n".utf8))
    }

    private static let usage = """
    Usage:
      label-driver validate INPUT.pdf --job-ticket ticket.json [--json]
      label-driver convert INPUT.pdf --job-ticket ticket.json --output output.zpl --preview-dir directory [--json]
    This offline tool never prints or contacts a printer.
    """
}

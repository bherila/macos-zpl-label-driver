import Darwin
import Foundation
import LabelCore

/// Result metadata for the private, versioned render-worker file protocol.
public struct OfflineRenderWorkerResult: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let widthDots: Int
    public let heightDots: Int
    public let zplBytes: Int
    public let previewBytes: Int

    public init(widthDots: Int, heightDots: Int, zplBytes: Int, previewBytes: Int) {
        self.schemaVersion = 1
        self.widthDots = widthDots
        self.heightDots = heightDots
        self.zplBytes = zplBytes
        self.previewBytes = previewBytes
    }
}

public struct OfflineRenderWorkerOutput: Equatable, Sendable {
    public let result: OfflineRenderWorkerResult
    public let zpl: Data
    public let previewPBM: Data
}

/// Sanitized failure metadata. It deliberately contains no source path,
/// document title, rendered content, or underlying framework description.
public struct OfflineRenderWorkerFailure: Codable, Equatable, Sendable {
    public enum Code: String, Codable, Equatable, Sendable {
        case jobTicketInvalid = "JOB_TICKET_INVALID"
        case inputUnsupported = "INPUT_UNSUPPORTED"
        case inputEncrypted = "INPUT_ENCRYPTED"
        case annotationsUnsupported = "INPUT_ANNOTATIONS_UNSUPPORTED"
        case pageOutOfRange = "PAGE_OUT_OF_RANGE"
        case limitExceeded = "LIMIT_EXCEEDED"
        case geometryInvalid = "GEOMETRY_INVALID"
        case renderFailed = "RENDER_FAILED"
        case preparationFailed = "PREPARATION_FAILED"
    }

    public let schemaVersion: Int
    public let code: Code

    public init(code: Code) {
        self.schemaVersion = 1
        self.code = code
    }
}

/// Thread-safe cancellation shared by signal handling and the blocking worker
/// coordinator. Cancellation terminates only the owned render subprocess.
public final class OfflineRenderWorkerCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    public init() {}

    public func cancel() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// Runs native PDF work outside the caller so a stuck framework call can be
/// interrupted without privilege. The child receives only a mode-0700 scratch
/// directory and fixed protocol filenames, never user-selected destinations.
public enum OfflineRenderWorkerProcess {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidDeadline
        case workerUnavailable
        case scratchUnavailable
        case timedOut
        case cancelled
        case workerFailed(status: Int32)
        case jobRejected(code: OfflineRenderWorkerFailure.Code)
        case invalidResult
        case outputLimitExceeded
    }

    public static let defaultDeadlineSeconds: Double = 60
    public static let maximumTicketBytes = 64 * 1024
    public static let maximumZPLBytes = 64 * 1024 * 1024
    public static let maximumPreviewBytes = 64 * 1024 * 1024
    public static let maximumResultBytes = 64 * 1024

    public static let inputFilename = "input.pdf"
    public static let ticketFilename = "ticket.json"
    public static let zplFilename = "prepared.zpl"
    public static let previewFilename = "preview.pbm"
    public static let resultFilename = "result.json"
    public static let failureFilename = "failure.json"

    public static func run(
        originalPDF: Data,
        ticketJSON: Data,
        workerExecutable: URL,
        deadlineSeconds: Double = defaultDeadlineSeconds,
        cancellation: OfflineRenderWorkerCancellation = .init()
    ) throws -> OfflineRenderWorkerOutput {
        try runJob(
            originalPDF: originalPDF, ticketJSON: ticketJSON,
            workerExecutable: workerExecutable, operationFlag: "--job-directory",
            deadlineSeconds: deadlineSeconds, cancellation: cancellation,
            readOutput: readRenderOutput
        )
    }

    /// Shared admission, private staging, termination and bounded result reads
    /// for the worker's fixed render and layout-analysis operations.
    static func runJob<Output>(
        originalPDF: Data, ticketJSON: Data, workerExecutable: URL,
        operationFlag: String, deadlineSeconds: Double,
        cancellation: OfflineRenderWorkerCancellation,
        readOutput: (URL) throws -> Output
    ) throws -> Output {
        guard operationFlag == "--job-directory" || operationFlag == "--analysis-directory" else {
            throw Error.invalidResult
        }
        guard deadlineSeconds.isFinite, deadlineSeconds > 0, deadlineSeconds <= defaultDeadlineSeconds else {
            throw Error.invalidDeadline
        }
        guard originalPDF.count <= OfflineConversion.maximumInputBytes,
              ticketJSON.count <= maximumTicketBytes else {
            throw Error.outputLimitExceeded
        }
        // A request cancelled before admission must not stage its source or
        // launch a child merely to terminate it on the first polling turn.
        guard !cancellation.isCancelled else { throw Error.cancelled }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .nanoseconds(Int64(deadlineSeconds * 1_000_000_000)))
        var executableStat = stat()
        guard lstat(workerExecutable.path, &executableStat) == 0,
              (executableStat.st_mode & S_IFMT) == S_IFREG,
              access(workerExecutable.path, X_OK) == 0 else {
            throw Error.workerUnavailable
        }

        let scratch = try makePrivateScratchDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        do {
            try writePrivate(originalPDF, to: scratch.appending(path: inputFilename))
            try writePrivate(ticketJSON, to: scratch.appending(path: ticketFilename))
        } catch {
            throw Error.scratchUnavailable
        }

        let process = Process()
        process.executableURL = workerExecutable
        process.arguments = [operationFlag, scratch.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            guard !cancellation.isCancelled else { throw Error.cancelled }
            guard clock.now < deadline else { throw Error.timedOut }
            try process.run()
        } catch Error.cancelled {
            throw Error.cancelled
        } catch Error.timedOut {
            throw Error.timedOut
        } catch {
            throw Error.workerUnavailable
        }

        while process.isRunning {
            if cancellation.isCancelled {
                stop(process)
                throw Error.cancelled
            }
            if clock.now >= deadline {
                stop(process)
                throw Error.timedOut
            }
            usleep(10_000)
        }
        process.waitUntilExit()
        guard !cancellation.isCancelled else { throw Error.cancelled }
        guard clock.now < deadline else { throw Error.timedOut }
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            if process.terminationReason == .exit, let failure = try? readFailure(in: scratch) {
                throw Error.jobRejected(code: failure.code)
            }
            throw Error.workerFailed(status: process.terminationStatus)
        }

        let output = try readOutput(scratch)
        guard !cancellation.isCancelled else { throw Error.cancelled }
        guard clock.now < deadline else { throw Error.timedOut }
        return output
    }

    private static func readRenderOutput(_ scratch: URL) throws -> OfflineRenderWorkerOutput {
        do {
            let resultData = try readPrivateRegularFile(
                scratch.appending(path: resultFilename), maximumBytes: maximumResultBytes
            )
            let result = try JSONDecoder().decode(OfflineRenderWorkerResult.self, from: resultData)
            guard result.schemaVersion == 1,
                  result.widthDots > 0, result.heightDots > 0,
                  result.zplBytes >= 0, result.zplBytes <= maximumZPLBytes,
                  result.previewBytes >= 0, result.previewBytes <= maximumPreviewBytes else {
                throw Error.invalidResult
            }
            let zpl = try readPrivateRegularFile(
                scratch.appending(path: zplFilename), maximumBytes: maximumZPLBytes
            )
            let preview = try readPrivateRegularFile(
                scratch.appending(path: previewFilename), maximumBytes: maximumPreviewBytes
            )
            guard zpl.count == result.zplBytes, preview.count == result.previewBytes else {
                throw Error.invalidResult
            }
            return OfflineRenderWorkerOutput(result: result, zpl: zpl, previewPBM: preview)
        } catch let error as Error {
            throw error
        } catch {
            throw Error.invalidResult
        }
    }

    public static func performJob(in directory: URL) throws {
        try validatePrivateScratchDirectory(directory)
        let source = try readPrivateRegularFile(
            directory.appending(path: inputFilename), maximumBytes: OfflineConversion.maximumInputBytes
        )
        let ticketData = try readPrivateRegularFile(
            directory.appending(path: ticketFilename), maximumBytes: maximumTicketBytes
        )
        let ticket = try OfflineConversionTicket(jsonData: ticketData)
        let prepared = try OfflineConversion.prepare(originalPDF: source, ticket: ticket)
        let preview = prepared.previewPBM
        guard prepared.zpl.count <= maximumZPLBytes, preview.count <= maximumPreviewBytes else {
            throw Error.outputLimitExceeded
        }
        try writePrivate(prepared.zpl, to: directory.appending(path: zplFilename))
        try writePrivate(preview, to: directory.appending(path: previewFilename))
        let result = OfflineRenderWorkerResult(
            widthDots: prepared.bitmap.layout.width,
            heightDots: prepared.bitmap.layout.height,
            zplBytes: prepared.zpl.count,
            previewBytes: preview.count
        )
        let resultData = try JSONEncoder.sorted.encode(result)
        guard resultData.count <= maximumResultBytes else { throw Error.outputLimitExceeded }
        try writePrivate(resultData, to: directory.appending(path: resultFilename))
    }

    /// Records only an allowlisted category after a failed worker job. The
    /// nonzero process status remains authoritative; malformed failure metadata
    /// is ignored by the parent in favor of a generic worker failure.
    public static func recordFailure(_ error: Swift.Error, in directory: URL) throws {
        try validatePrivateScratchDirectory(directory)
        let failure = classifyFailure(error)
        let data = try JSONEncoder.sorted.encode(failure)
        guard data.count <= maximumResultBytes else { throw Error.outputLimitExceeded }
        try writePrivate(data, to: directory.appending(path: failureFilename))
    }

    static func classifyFailure(_ error: Swift.Error) -> OfflineRenderWorkerFailure {
        let code: OfflineRenderWorkerFailure.Code
        switch error {
        case is OfflineConversionTicket.TicketError:
            code = .jobTicketInvalid
        case QuartzPDFRenderer.Error.malformedOrUnsupportedPDF:
            code = .inputUnsupported
        case QuartzPDFRenderer.Error.encryptedPDF:
            code = .inputEncrypted
        case QuartzPDFRenderer.Error.annotationsUnsupported:
            code = .annotationsUnsupported
        case QuartzPDFRenderer.Error.invalidPageGeometry:
            code = .geometryInvalid
        case QuartzPDFRenderer.Error.pageOutOfRange:
            code = .pageOutOfRange
        case QuartzPDFRenderer.Error.inputTooLarge,
             QuartzPDFRenderer.Error.sourcePageLimitExceeded,
             QuartzPDFRenderer.Error.pixelLimitExceeded,
             QuartzPDFRenderer.Error.allocationOverflow,
             QuartzPDFRenderer.Error.invalidLimits,
             is BitmapLayout.ValidationError,
             ZPLGraphicEncoder.EncodingError.outputLimit,
             ZPLGraphicEncoder.EncodingError.coordinateLimit,
             OfflineRenderWorkerProcess.Error.outputLimitExceeded:
            code = .limitExceeded
        case is PhysicalGeometryError, is PageGeometryError:
            code = .geometryInvalid
        case QuartzPDFRenderer.Error.contextUnavailable:
            code = .renderFailed
        default:
            code = .preparationFailed
        }
        return OfflineRenderWorkerFailure(code: code)
    }

    private static func makePrivateScratchDirectory() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appending(path: "label-driver-worker.XXXXXX").path
        var template = Array(base.utf8CString)
        guard let pointer = mkdtemp(&template) else { throw Error.scratchUnavailable }
        let directory = URL(fileURLWithPath: String(cString: pointer), isDirectory: true)
        guard chmod(directory.path, S_IRWXU) == 0 else {
            try? FileManager.default.removeItem(at: directory)
            throw Error.scratchUnavailable
        }
        return directory
    }

    static func validatePrivateScratchDirectory(_ directory: URL) throws {
        var info = stat()
        guard lstat(directory.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == geteuid(),
              (info.st_mode & (S_IRWXG | S_IRWXO)) == 0 else {
            throw Error.scratchUnavailable
        }
    }

    private static func readFailure(in directory: URL) throws -> OfflineRenderWorkerFailure {
        let data = try readPrivateRegularFile(
            directory.appending(path: failureFilename), maximumBytes: maximumResultBytes
        )
        let failure = try JSONDecoder().decode(OfflineRenderWorkerFailure.self, from: data)
        guard failure.schemaVersion == 1 else { throw Error.invalidResult }
        return failure
    }

    static func writePrivate(_ data: Data, to url: URL) throws {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw Error.scratchUnavailable }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: url)
            throw Error.scratchUnavailable
        }
    }

    static func readPrivateRegularFile(_ url: URL, maximumBytes: Int) throws -> Data {
        do {
            return try BoundedRegularFile.read(
                url,
                maximumBytes: maximumBytes,
                requireCurrentUserOwner: true,
                requireSingleLink: true
            )
        } catch BoundedRegularFile.Error.tooLarge {
            throw Error.outputLimitExceeded
        } catch {
            throw Error.invalidResult
        }
    }

    private static func stop(_ process: Process) {
        process.terminate()
        let limit = ContinuousClock.now.advanced(by: .milliseconds(500))
        while process.isRunning, ContinuousClock.now < limit { usleep(10_000) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

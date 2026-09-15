import Darwin
import Foundation

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

    fileprivate var isCancelled: Bool {
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

    public static func run(
        originalPDF: Data,
        ticketJSON: Data,
        workerExecutable: URL,
        deadlineSeconds: Double = defaultDeadlineSeconds,
        cancellation: OfflineRenderWorkerCancellation = .init()
    ) throws -> OfflineRenderWorkerOutput {
        guard deadlineSeconds.isFinite, deadlineSeconds > 0, deadlineSeconds <= defaultDeadlineSeconds else {
            throw Error.invalidDeadline
        }
        guard originalPDF.count <= OfflineConversion.maximumInputBytes,
              ticketJSON.count <= maximumTicketBytes else {
            throw Error.outputLimitExceeded
        }
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
        process.arguments = ["--job-directory", scratch.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw Error.workerUnavailable
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .milliseconds(Int64(deadlineSeconds * 1_000)))
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
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw Error.workerFailed(status: process.terminationStatus)
        }

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

    private static func validatePrivateScratchDirectory(_ directory: URL) throws {
        var info = stat()
        guard lstat(directory.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == geteuid(),
              (info.st_mode & (S_IRWXG | S_IRWXO)) == 0 else {
            throw Error.scratchUnavailable
        }
    }

    private static func writePrivate(_ data: Data, to url: URL) throws {
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

    private static func readPrivateRegularFile(_ url: URL, maximumBytes: Int) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw Error.invalidResult }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == geteuid(),
              info.st_nlink == 1,
              info.st_size >= 0,
              info.st_size <= maximumBytes else {
            throw Error.outputLimitExceeded
        }
        let data = try handle.readToEnd() ?? Data()
        guard data.count <= maximumBytes else { throw Error.outputLimitExceeded }
        return data
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

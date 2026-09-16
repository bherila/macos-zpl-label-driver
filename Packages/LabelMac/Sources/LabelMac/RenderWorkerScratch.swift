import Darwin
import Foundation

enum RenderWorkerScratch {
    static let markerName = "ownership.json"
    static let prefix = "label-driver-worker."
    static let filenames: Set<String> = [markerName, "input.pdf", "ticket.json", "prepared.zpl",
                                        "preview.pbm", "result.json", "failure.json", "layout.json"]

    struct Record: Codable, Equatable {
        let schemaVersion: Int
        let parentPID: Int32
        let ownerUID: UInt32
        let device: Int64
        let inode: UInt64
        let token: String
    }

    struct Ownership {
        let descriptor: Int32
        let token: String
    }

    static func install(in directory: URL, parentPID: Int32 = getpid()) throws -> Ownership {
        var info = stat()
        guard parentPID > 1, lstat(directory.path, &info) == 0, privateDirectory(info) else {
            throw OfflineRenderWorkerProcess.Error.scratchUnavailable
        }
        let token = UUID().uuidString.lowercased()
        let record = Record(schemaVersion: 1, parentPID: parentPID, ownerUID: geteuid(),
                            device: Int64(info.st_dev), inode: UInt64(info.st_ino), token: token)
        try OfflineRenderWorkerProcess.writePrivate(encode(record),
            to: directory.appending(path: markerName))
        let descriptor = NonblockingRegularFileDescriptor.open(path: directory.appending(path: markerName).path)
        guard descriptor >= 0 else { throw OfflineRenderWorkerProcess.Error.scratchUnavailable }
        guard flock(descriptor, LOCK_SH | LOCK_NB) == 0 else {
            close(descriptor)
            throw OfflineRenderWorkerProcess.Error.scratchUnavailable
        }
        return Ownership(descriptor: descriptor, token: token)
    }

    static func hold(in directory: URL, parentPID: Int32, token: String) throws -> Int32 {
        let root = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard root >= 0 else { throw OfflineRenderWorkerProcess.Error.scratchUnavailable }
        defer { close(root) }
        let marker = NonblockingRegularFileDescriptor.open(at: root, name: markerName)
        guard marker >= 0 else { throw OfflineRenderWorkerProcess.Error.scratchUnavailable }
        do {
            guard flock(marker, LOCK_SH | LOCK_NB) == 0 else {
                throw OfflineRenderWorkerProcess.Error.scratchUnavailable
            }
            let record = try readRecord(marker: marker, directory: root)
            guard record.parentPID == parentPID, record.token == token else {
                throw OfflineRenderWorkerProcess.Error.scratchUnavailable
            }
            return marker
        } catch {
            close(marker)
            throw error
        }
    }

    private static func privateDirectory(_ info: stat) -> Bool {
        (info.st_mode & S_IFMT) == S_IFDIR && info.st_uid == geteuid()
            && (info.st_mode & (S_IRWXG | S_IRWXO)) == 0
    }

    private static func encode(_ record: Record) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(record)
    }

    private static func readRecord(marker: Int32, directory: Int32) throws -> Record {
        var info = stat()
        var markerInfo = stat()
        guard fstat(directory, &info) == 0, privateDirectory(info),
              fstat(marker, &markerInfo) == 0,
              (markerInfo.st_mode & (S_IRWXG | S_IRWXO)) == 0 else {
            throw OfflineRenderWorkerProcess.Error.scratchUnavailable
        }
        let data = try BoundedRegularFile.read(openFileDescriptor: marker, maximumBytes: 4_096,
            requireCurrentUserOwner: true, requireSingleLink: true)
        let record = try JSONDecoder().decode(Record.self, from: data)
        guard record.schemaVersion == 1, record.parentPID > 1, record.ownerUID == geteuid(),
              record.device == Int64(info.st_dev), record.inode == UInt64(info.st_ino),
              UUID(uuidString: record.token)?.uuidString.lowercased() == record.token,
              try encode(record) == data else {
            throw OfflineRenderWorkerProcess.Error.scratchUnavailable
        }
        return record
    }

    static func recover(in base: URL, maximumEntries: Int = 4_096,
                        maximumCandidates: Int = 128) throws -> RenderWorkerScratchRecoveryReport {
        guard (1...4_096).contains(maximumEntries), (1...128).contains(maximumCandidates) else {
            throw OfflineRenderWorkerProcess.Error.invalidResult
        }
        let root = open(base.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard root >= 0 else { throw OfflineRenderWorkerProcess.Error.scratchUnavailable }
        defer { close(root) }
        var baseInfo = stat()
        guard fstat(root, &baseInfo) == 0, privateDirectory(baseInfo) else {
            throw OfflineRenderWorkerProcess.Error.scratchUnavailable
        }
        let enumeration = dup(root)
        guard enumeration >= 0 else { throw OfflineRenderWorkerProcess.Error.scratchUnavailable }
        guard let stream = fdopendir(enumeration) else {
            close(enumeration)
            throw OfflineRenderWorkerProcess.Error.scratchUnavailable
        }
        defer { closedir(stream) }
        var report = RenderWorkerScratchRecoveryReport()
        var entries = 0
        var candidates = 0
        while true {
            errno = 0
            guard let entry = readdir(stream) else {
                if errno != 0 { report.truncated = true }
                break
            }
            entries += 1
            guard entries <= maximumEntries else { report.truncated = true; break }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            guard name.hasPrefix(prefix) else { continue }
            let suffix = Array(name.dropFirst(prefix.count).utf8)
            guard suffix.count == 6, suffix.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else {
                continue
            }
            candidates += 1
            guard candidates <= maximumCandidates else { report.truncated = true; break }
            switch recoverCandidate(in: root, name: name) {
            case .removed: report.removed += 1
            case .active: report.active += 1
            case .retained: report.requiresReview += 1
            }
        }
        return report
    }

    private enum Outcome { case removed, active, retained }

    private static func recoverCandidate(in base: Int32, name: String) -> Outcome {
        let directory = openat(base, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { return .retained }
        defer { close(directory) }
        let marker = NonblockingRegularFileDescriptor.open(at: directory, name: markerName)
        guard marker >= 0 else { return .retained }
        defer { close(marker) }
        do {
            let record = try readRecord(marker: marker, directory: directory)
            // PID reuse deliberately retains data; liveness is not proof of the
            // original parent, and ambiguity cannot authorize deletion.
            guard kill(record.parentPID, 0) != 0, errno == ESRCH else { return .active }
            guard flock(marker, LOCK_EX | LOCK_NB) == 0 else { return .active }
            // Shared locks cover the parent and actual child until process exit.
            // No cooperative parser/writer can still be using this directory.
            let enumeration = openat(directory, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
            guard enumeration >= 0 else { return .retained }
            guard let stream = fdopendir(enumeration) else {
                close(enumeration)
                return .retained
            }
            defer { closedir(stream) }
            var names: [String] = []
            while true {
                errno = 0
                guard let entry = readdir(stream) else {
                    if errno != 0 { return .retained }
                    break
                }
                let filename = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                if filename == "." || filename == ".." { continue }
                guard filenames.contains(filename), names.count < filenames.count else { return .retained }
                var info = stat()
                guard fstatat(directory, filename, &info, AT_SYMLINK_NOFOLLOW) == 0,
                      (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == geteuid(), info.st_nlink == 1,
                      (info.st_mode & (S_IRWXG | S_IRWXO)) == 0 else { return .retained }
                names.append(filename)
            }
            var current = stat()
            guard fstatat(base, name, &current, AT_SYMLINK_NOFOLLOW) == 0,
                  current.st_dev == record.device, UInt64(current.st_ino) == record.inode else { return .retained }
            for filename in names where filename != markerName {
                guard unlinkat(directory, filename, 0) == 0 else { return .retained }
            }
            guard unlinkat(directory, markerName, 0) == 0 else { return .retained }
            if unlinkat(base, name, AT_REMOVEDIR) == 0 { return .removed }
            // Preserve recovery identity when namespace removal fails.
            let restored = openat(directory, markerName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
            if restored >= 0 {
                let handle = FileHandle(fileDescriptor: restored, closeOnDealloc: true)
                try? handle.write(contentsOf: encode(record))
                try? handle.close()
            }
            return .retained
        } catch {
            return .retained
        }
    }
}

public struct RenderWorkerScratchRecoveryReport: Equatable, Sendable {
    public internal(set) var removed = 0
    public internal(set) var active = 0
    public internal(set) var requiresReview = 0
    public internal(set) var truncated = false
}

extension OfflineRenderWorkerProcess {
    /// Recovery is ancillary: an unavailable scan must not disable setup.
    /// Errors are sanitized and never authorize broader cleanup.
    public static func scratchRecoveryWarning(
        scan: () throws -> RenderWorkerScratchRecoveryReport = { try recoverAbandonedScratch() }
    ) -> String? {
        do {
            let report = try scan()
            if report.requiresReview > 0 || report.truncated {
                return "Some temporary worker data require manual review; they were not removed."
            }
            return nil
        } catch {
            return "Temporary worker recovery is unavailable. Retained data may require manual review."
        }
    }

    /// Removes only proven-owned, dead-parent, unlocked scratch directories.
    /// Legacy/unmarked/ambiguous material is reported, never adopted or purged.
    public static func recoverAbandonedScratch() throws -> RenderWorkerScratchRecoveryReport {
        try RenderWorkerScratch.recover(in: FileManager.default.temporaryDirectory)
    }
}

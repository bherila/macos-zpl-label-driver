import CryptoKit
import Darwin
import Foundation

/// Exact packed previews only. No ZPL, transport, status query or admission.
public enum PackedFinishingPreviewExport {
    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidLimit, byteLimit, invalidDestination, cannotWrite, destinationExists, commitUncertain
    }
    public static func write(_ prepared: PreparedAcceptedFinishingJob, toNewDirectory destination: URL,
                             maximumBytes: Int = 512 * 1024 * 1024,
                             deadlineSeconds: Double = 60,
                             cancellation: OfflineRenderWorkerCancellation = .init()) throws {
        guard (1...(512 * 1024 * 1024)).contains(maximumBytes), deadlineSeconds.isFinite,
              deadlineSeconds > 0, deadlineSeconds <= 60 else { throw Error.invalidLimit }
        let start = DispatchTime.now().uptimeNanoseconds
        func check() throws {
            guard !cancellation.isCancelled else { throw AcceptedFinishingJob.Error.cancelled }
            guard Double(DispatchTime.now().uptimeNanoseconds-start)/1_000_000_000 < deadlineSeconds else { throw AcceptedFinishingJob.Error.timedOut }
        }
        try check()
        let rasters = prepared.preparation.rasters
        guard !rasters.isEmpty, rasters.count <= 10_000 else { throw Error.invalidLimit }
        var total = 0, entries: [[String:Any]] = []
        for (index,raster) in rasters.enumerated() {
            try check()
            let header = "P4\n\(raster.layout.width) \(raster.layout.height)\n"
            let (bytes,overflow) = raster.bytes.count.addingReportingOverflow(header.utf8.count)
            let (next,sumOverflow) = total.addingReportingOverflow(bytes)
            guard !overflow, !sumOverflow, next <= maximumBytes else { throw Error.byteLimit }
            total = next
            entries.append(["ordinal":index+1,"file":String(format:"label-%05d.pbm",index+1),
                "widthDots":raster.layout.width,"heightDots":raster.layout.height,
                "packedSHA256":SHA256.hash(data:Data(raster.bytes)).map { String(format:"%02x",$0) }.joined()])
        }
        let manifest = try JSONSerialization.data(withJSONObject:["kind":"offline-packed-finishing-preview","schemaVersion":1,
            "acceptedRecordSHA256":prepared.reference.sha256,"sourceSHA256":prepared.acceptance.sourceSHA256,
            "hardwareCompletion":"unknown","labels":entries],options:[.sortedKeys])
        let (complete,overflow) = total.addingReportingOverflow(manifest.count)
        guard !overflow, complete <= maximumBytes, manifest.count <= 4 * 1024 * 1024 else { throw Error.byteLimit }
        let name = destination.lastPathComponent
        guard destination.isFileURL, !name.isEmpty, name != ".", name != "..", !name.contains("/"),
              !name.utf8.contains(0) else { throw Error.invalidDestination }
        let parent = open(destination.deletingLastPathComponent().path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard parent >= 0 else { throw Error.invalidDestination }
        defer { close(parent) }
        var parentInfo = stat()
        guard fstat(parent,&parentInfo) == 0, parentInfo.st_uid == getuid(),
              parentInfo.st_mode & 0o022 == 0 else { throw Error.invalidDestination }
        let temporary = ".packed-preview-" + UUID().uuidString
        guard mkdirat(parent,temporary,0o700) == 0 else { throw Error.cannotWrite }
        var created = stat()
        guard fstatat(parent,temporary,&created,AT_SYMLINK_NOFOLLOW) == 0 else { throw Error.cannotWrite }
        let directory = openat(parent,temporary,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
        guard directory >= 0 else {
            var named = stat()
            if fstatat(parent,temporary,&named,AT_SYMLINK_NOFOLLOW) == 0,
               named.st_dev == created.st_dev, named.st_ino == created.st_ino {
                _ = unlinkat(parent,temporary,AT_REMOVEDIR)
            }
            throw Error.cannotWrite
        }
        var names: [String] = [], published = false
        defer {
            if !published {
                for file in names { _ = unlinkat(directory,file,0) }
                var held = stat(), named = stat()
                if fstat(directory,&held) == 0, fstatat(parent,temporary,&named,AT_SYMLINK_NOFOLLOW) == 0,
                   held.st_dev == named.st_dev, held.st_ino == named.st_ino {
                    _ = unlinkat(parent,temporary,AT_REMOVEDIR)
                }
            }
            close(directory)
        }
        func file(_ name:String, _ bytes:Data) throws {
            try check()
            let fd = openat(directory,name,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600)
            guard fd >= 0 else { throw Error.cannotWrite }; names.append(name)
            defer { close(fd) }
            try bytes.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    try check()
                    let written = Darwin.write(fd,buffer.baseAddress!.advanced(by:offset),min(64*1024,buffer.count-offset))
                    if written < 0, errno == EINTR { continue }
                    guard written > 0 else { throw Error.cannotWrite }; offset += written
                }
            }
            guard fsync(fd) == 0 else { throw Error.cannotWrite }
        }
        for (index,raster) in rasters.enumerated() { try check(); try file(String(format:"label-%05d.pbm",index+1),raster.pbmData()) }
        try file("preview.json",manifest);try check()
        guard fsync(directory) == 0 else { throw Error.cannotWrite }
        var held = stat(), named = stat()
        guard fstat(directory,&held) == 0, fstatat(parent,temporary,&named,AT_SYMLINK_NOFOLLOW) == 0,
              held.st_dev == created.st_dev, held.st_ino == created.st_ino,
              held.st_dev == named.st_dev, held.st_ino == named.st_ino else { throw Error.cannotWrite }
        guard renameatx_np(parent,temporary,parent,name,UInt32(RENAME_EXCL)) == 0 else {
            if errno == EEXIST { throw Error.destinationExists }; throw Error.cannotWrite
        }
        published = true
        guard fsync(parent) == 0 else { throw Error.commitUncertain }
        do { try check() } catch { throw Error.commitUncertain }
    }
}

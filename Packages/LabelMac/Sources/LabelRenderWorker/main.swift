import Darwin
import Foundation
import LabelMac

@main
struct LabelRenderWorker {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 2 || arguments.count == 8,
              arguments[0] == "--job-directory" || arguments[0] == "--analysis-directory" else {
            fail(status: 64)
        }
        var supervisor: RenderWorkerSupervisor?
        defer { supervisor?.stop() }
        do {
            let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
            var parentPID = getppid()
            var deadlineSeconds = 60.0
            var token: String?
            if arguments.count == 8 {
                guard arguments[2] == "--parent-pid", let pid = Int32(arguments[3]),
                      arguments[4] == "--deadline-seconds", let seconds = Double(arguments[5]),
                      arguments[6] == "--ownership-token" else { fail(status: 64) }
                parentPID = pid
                deadlineSeconds = seconds
                token = arguments[7]
            }
            supervisor = try RenderWorkerSupervisor(parentPID: parentPID,
                deadlineSeconds: deadlineSeconds, scratchDirectory: token == nil ? nil : directory,
                ownershipToken: token)
            if arguments[0] == "--analysis-directory" {
                try OfflineRenderWorkerProcess.performLayoutAnalysis(in: directory)
            } else {
                try OfflineRenderWorkerProcess.performJob(in: directory)
            }
        } catch {
            try? OfflineRenderWorkerProcess.recordFailure(
                error,
                in: URL(fileURLWithPath: arguments[1], isDirectory: true)
            )
            fail(status: 65)
        }
    }

    private static func fail(status: Int32) -> Never {
        FileHandle.standardError.write(Data("label-render-worker: preparation failed\n".utf8))
        exit(status)
    }
}

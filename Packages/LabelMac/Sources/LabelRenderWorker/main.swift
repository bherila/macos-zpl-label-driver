import Darwin
import Foundation
import LabelMac

@main
struct LabelRenderWorker {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 2,
              arguments[0] == "--job-directory" || arguments[0] == "--analysis-directory" else {
            fail(status: 64)
        }
        do {
            let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
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

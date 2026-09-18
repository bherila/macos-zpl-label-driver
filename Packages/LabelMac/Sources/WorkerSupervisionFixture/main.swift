import Darwin
import Foundation
import LabelMac

// Test-only, finite main-thread hold. It proves supervisor behavior, not PDF
// rendering or printer acceptance. It is never included in the setup bundle.
@main
struct WorkerSupervisionFixture {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 1 || args.count == 3, let seconds = Double(args[0]) else { _exit(64) }
        do {
            let supervisor = try RenderWorkerSupervisor(parentPID: getppid(), deadlineSeconds: seconds,
                scratchDirectory: args.count == 3 ? URL(fileURLWithPath: args[1]) : nil,
                ownershipToken: args.count == 3 ? args[2] : nil)
            FileHandle.standardOutput.write(Data("ready\n".utf8))
            usleep(10_000_000)
            supervisor.stop()
        } catch { _exit(65) }
    }
}

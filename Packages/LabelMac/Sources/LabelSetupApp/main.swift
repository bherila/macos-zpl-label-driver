import Foundation
import Combine
import SwiftUI
import UniformTypeIdentifiers
import LabelMac

@MainActor
final class SetupAppController: ObservableObject {
    @Published var editor: WorkflowEditorModel?
    @Published var error: String?
    @Published var scratchWarning: String?

    private let store: WorkflowProfileStore?
    let printerSetup: ReferencePrinterSetupModel?
    let previewWorkerExecutable = (Bundle.main.executableURL?.deletingLastPathComponent()
        ?? Bundle.main.bundleURL.appending(path: "Contents/MacOS"))
        .appending(path: "label-render-worker")

    init() {
        scratchWarning = OfflineRenderWorkerProcess.scratchRecoveryWarning()
        do {
            let setup = try ReferencePrinterSetupModel.gc420dUSB()
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appending(path: "LabelPrinterDriver", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(
                at: support,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let profileStore = try WorkflowProfileStore(root: support.appending(path: "profiles-v1"))
            printerSetup = setup
            store = profileStore
        } catch {
            store = nil
            printerSetup = nil
            self.error = String(describing: error)
        }
    }

    func open(_ url: URL) {
        guard let store else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try BoundedRegularFile.read(url, maximumBytes: 100 * 1024 * 1024)
            editor = try WorkflowEditorBootstrap.makeModel(originalPDF: data, store: store)
            error = nil
        } catch {
            editor = nil
            self.error = String(describing: error)
        }
    }
}

struct SetupRootView: View {
    @ObservedObject var controller: SetupAppController
    @State private var importing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let warning = controller.scratchWarning {
                    Text(warning).foregroundStyle(.orange)
                        .accessibilityLabel(warning)
                }
                if let printerSetup = controller.printerSetup {
                    ReferencePrinterSetupView(model: printerSetup)
                }
                Group {
                    if let editor = controller.editor {
                        WorkflowEditorView(model: editor, workerExecutable: controller.previewWorkerExecutable)
                    } else {
                        ContentUnavailableView {
                            Label("Create a label workflow", systemImage: "printer")
                        } description: {
                            Text("Confirm the stock and tear-off setup above, then open a local PDF. Nothing is uploaded or printed.")
                        } actions: {
                            Button("Open PDF…") { importing = true }
                                .keyboardShortcut("o", modifiers: [.command])
                                .disabled(!(controller.printerSetup?.canEditOfflineWorkflows ?? false))
                        }
                    }
                }
            }
            .padding()
        }
        .frame(minWidth: 820, minHeight: 760)
        .overlay(alignment: .bottom) {
            if let error = controller.error {
                Text(error).foregroundStyle(.red).padding()
                    .accessibilityLabel("Setup error: \(error)")
            } else {
                Text("Local ad-hoc development build")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
            if case let .success(url) = result { controller.open(url) }
            if case let .failure(error) = result { controller.error = String(describing: error) }
        }
    }
}

@main
struct LabelPrinterSetupApp: App {
    @StateObject private var controller = SetupAppController()

    var body: some Scene {
        WindowGroup("Label Printer Driver Setup") {
            SetupRootView(controller: controller)
        }
    }
}

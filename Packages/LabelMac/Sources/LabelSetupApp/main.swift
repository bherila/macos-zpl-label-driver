import Foundation
import Combine
import SwiftUI
import UniformTypeIdentifiers
import LabelMac

@MainActor
final class SetupAppController: ObservableObject {
    @Published var error: String?
    @Published var scratchWarning: String?

    let documents: WorkflowDocumentOpeningModel?
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
            documents = WorkflowDocumentOpeningModel(store: profileStore,
                workerExecutable: previewWorkerExecutable)
        } catch {
            documents = nil
            printerSetup = nil
            self.error = String(describing: error)
        }
    }

}

struct SetupRootView: View {
    @ObservedObject var controller: SetupAppController

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
                    if let documents = controller.documents {
                        SetupDocumentView(documents: documents,
                            workerExecutable: controller.previewWorkerExecutable,
                            canOpen: controller.printerSetup?.canEditOfflineWorkflows ?? false)
                    } else {
                        ContentUnavailableView {
                            Label("Create a label workflow", systemImage: "printer")
                        } description: {
                            Text("Confirm the stock and tear-off setup above, then open a local PDF. Nothing is uploaded or printed.")
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
    }
}

struct SetupDocumentView: View {
    @ObservedObject var documents: WorkflowDocumentOpeningModel
    let workerExecutable: URL
    let canOpen: Bool
    @State private var importing = false
    @State private var openingMode: WorkflowOpeningMode = .assisted

    var body: some View {
        VStack {
            if documents.isOpening {
                ProgressView("Preparing local PDF…")
                Button("Cancel Opening") { documents.cancelOpening() }
            } else if let editor = documents.editor {
                WorkflowEditorView(model: editor, workerExecutable: workerExecutable)
            } else {
                Text("Open a local PDF to create an offline label workflow.")
            }
            Button("Open PDF…") { openingMode = .assisted; importing = true }
                .keyboardShortcut("o", modifiers: [.command])
                .disabled(!canOpen || documents.isOpening)
            Button("Open PDF for Manual Extraction…") { openingMode = .manual; importing = true }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(!canOpen || documents.isOpening)
            if let error = documents.error { Text(error).foregroundStyle(.red) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
            if case let .success(url) = result { documents.open(url, mode: openingMode) }
            if case .failure = result { documents.reportImportFailure() }
        }
        .onDisappear { documents.cancelOpening() }
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

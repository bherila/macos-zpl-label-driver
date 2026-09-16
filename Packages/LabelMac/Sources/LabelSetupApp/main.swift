import Foundation
import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import LabelMac

@MainActor
final class SetupAppController: ObservableObject {
    @Published var error: String?
    @Published var scratchWarning: String?
    @Published var diagnosticCopyStatus: String?

    let documents: WorkflowDocumentOpeningModel?
    let printerSetup: ReferencePrinterSetupModel?
    let usbDiscovery = USBRegistryDiscoveryModel()
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

    func copyOfflineDiagnostics() {
        let report = OfflineSetupDiagnostics(documents: documents,
            setupAvailable: printerSetup != nil, setupErrorPresent: error != nil,
            scratchWarningPresent: scratchWarning != nil)
        NSPasteboard.general.clearContents()
        diagnosticCopyStatus = NSPasteboard.general.setString(report.text, forType: .string)
            ? "Offline diagnostics copied. Review before sharing; this is not installation or printer acceptance."
            : "Offline diagnostics could not be copied. No document or printer data was exported."
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
                USBRegistryDiscoveryView(model: controller.usbDiscovery)
                GroupBox("Offline diagnostics") {
                    VStack(alignment: .leading) {
                        Button("Copy Offline Diagnostics") { controller.copyOfflineDiagnostics() }
                        Text("Copies only offline state flags, without PDFs, paths, profile or printer identifiers, or error details. This replaces the clipboard contents; other apps may read copied text. Nothing is uploaded.")
                            .font(.caption)
                        if let status = controller.diagnosticCopyStatus {
                            Text(status).accessibilityLabel(status)
                        }
                    }
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
    @State private var selectedSavedWorkflow: String?
    @State private var reopeningProfile: WorkflowProfileStore.CatalogEntry?

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
            Button("Open PDF…") { reopeningProfile = nil; openingMode = .assisted; importing = true }
                .keyboardShortcut("o", modifiers: [.command])
                .disabled(!canOpen || documents.isOpening)
            Button("Open PDF for Manual Extraction…") { reopeningProfile = nil; openingMode = .manual; importing = true }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(!canOpen || documents.isOpening)
            GroupBox("Saved workflow revisions") {
                VStack(alignment: .leading) {
                    Picker("Saved workflow", selection: $selectedSavedWorkflow) {
                        Text("Choose a saved revision").tag(nil as String?)
                        ForEach(documents.savedWorkflows) { entry in
                            Text("\(entry.profile.id) — revision \(entry.profile.revision)")
                                .tag(Optional(entry.id))
                        }
                    }
                    Button("Reopen Saved Workflow with PDF…") {
                        reopeningProfile = documents.savedWorkflows.first { $0.id == selectedSavedWorkflow }
                        if reopeningProfile != nil { importing = true }
                    }.disabled(!canOpen || documents.isOpening ||
                        !documents.savedWorkflows.contains { $0.id == selectedSavedWorkflow })
                    Button("Refresh Saved Workflows") { Task { await documents.refreshSavedWorkflows() } }
                        .disabled(documents.isRefreshingSavedWorkflows)
                    if documents.isRefreshingSavedWorkflows { ProgressView("Reading saved workflows…") }
                    if let error = documents.savedWorkflowError { Text(error).foregroundStyle(.red) }
                    Text("Choose a local source PDF. Reopening verifies page geometry and configured layout anchors and creates a new unsaved revision. Manual regions require visual review; nothing is printed or replayed.")
                        .font(.caption)
                }
            }
            if let error = documents.error { Text(error).foregroundStyle(.red) }
            WorkflowProfileTransferView(model: documents,
                selectedProfile: documents.savedWorkflows.first { $0.id == selectedSavedWorkflow }?.profile)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
            if case let .success(url) = result {
                if let reopeningProfile { documents.openSavedWorkflow(url, profile: reopeningProfile.profile) }
                else { documents.open(url, mode: openingMode) }
            }
            if case .failure = result { documents.reportImportFailure() }
        }
        .task { await documents.refreshSavedWorkflows() }
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

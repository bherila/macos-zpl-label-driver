import Foundation
import Combine
import SwiftUI
import UniformTypeIdentifiers
import LabelMac

@MainActor
final class SetupAppController: ObservableObject {
    @Published var editor: WorkflowEditorModel?
    @Published var error: String?

    private let store: WorkflowProfileStore?

    init() {
        do {
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
            store = try WorkflowProfileStore(root: support.appending(path: "profiles-v1"))
        } catch {
            store = nil
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
        Group {
            if let editor = controller.editor {
                WorkflowEditorView(model: editor)
            } else {
                ContentUnavailableView {
                    Label("Create a label workflow", systemImage: "printer")
                } description: {
                    Text("Open a local PDF to detect bordered labels. Nothing is uploaded or printed.")
                } actions: {
                    Button("Open PDF…") { importing = true }
                        .keyboardShortcut("o", modifiers: [.command])
                }
            }
        }
        .frame(minWidth: 760, minHeight: 560)
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

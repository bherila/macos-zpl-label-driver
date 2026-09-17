import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct FinishingInspectionView: View {
    @ObservedObject private var model: FinishingInspectionModel
    @State private var importing = false
    public init(model: FinishingInspectionModel) { self.model = model }
    public var body: some View {
        GroupBox("Saved finishing jobs") {
            VStack(alignment: .leading, spacing: 8) {
                Button("Open Saved Job…") { importing = true }.disabled(model.isBusy)
                if model.isBusy {
                    ProgressView("Verifying or exporting saved job…")
                    Button("Cancel") { model.cancel() }
                }
                if let summary = model.summary {
                    Text("\(summary.outputLabelCount) labels · \(summary.canvasWidthDots) × \(summary.canvasHeightDots) dots")
                    Text(summary.localIntent == "uncertain-after-recorded-intent"
                        ? "A delivery attempt was recorded; its outcome is uncertain."
                        : "No local delivery intent was recorded. This does not prove that the job was never sent.")
                    if summary.cancellationRequested { Text("Cancellation was requested.") }
                    Text("Hardware completion is unknown. Automatic replay is not authorized.").font(.caption)
                    Button("Export Packed Previews…") { chooseExportParent() }.disabled(model.isBusy)
                }
                if let status = model.status { Text(status).accessibilityLabel(status) }
                Text("Opens an existing saved job for inspection and exact preview export. Nothing is printed.").font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fileImporter(isPresented: $importing,
            allowedContentTypes: [UTType(filenameExtension: "bin") ?? .data], allowsMultipleSelection: false) { result in
            if case let .success(files) = result, let file = files.first {
                Task {
                    let scoped = file.startAccessingSecurityScopedResource()
                    defer { if scoped { file.stopAccessingSecurityScopedResource() } }
                    await model.open(file)
                }
            }
        }
    }
    private func chooseExportParent() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = "Export Here"
        panel.message = "Packed previews contain the label content and a manifest with document hashes. Review these files before sharing them. Choose a folder for a new preview subfolder; existing output is preserved."
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        let destination = parent.appendingPathComponent("Packed Previews " + UUID().uuidString, isDirectory: true)
        Task {
            let scoped = parent.startAccessingSecurityScopedResource()
            defer { if scoped { parent.stopAccessingSecurityScopedResource() } }
            await model.exportPreviews(toNewDirectory: destination)
        }
    }
}

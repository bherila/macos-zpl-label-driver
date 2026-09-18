import Foundation
import LabelCore
import SwiftUI
import UniformTypeIdentifiers

/// Definition-only user-session transfer. No source document or approval is copied.
public enum WorkflowProfileTransfer {
    public static func readImport(_ url: URL) throws -> WorkflowProfile {
        guard url.isFileURL else { throw BoundedRegularFile.Error.cannotOpen }
        let bytes = try BoundedRegularFile.read(url, maximumBytes: WorkflowProfileJSON.maximumBytes)
        let imported = try WorkflowProfileJSON.decode(bytes)
        return try WorkflowProfile(schemaVersion: imported.schemaVersion, id: "import-" + UUID().uuidString.lowercased(), revision: 1,
            outputStockID: imported.outputStockID, outputStock: imported.outputStock,
            outputMargins: imported.outputMargins, monochromeConversion: imported.monochromeConversion, pageRules: imported.pageRules)
    }

    public static func exportSnapshot(_ snapshot: WorkflowProfile, store: WorkflowProfileStore) throws -> Data {
        guard try store.load(profileID: snapshot.id, revision: snapshot.revision) == snapshot else {
            throw WorkflowProfileStore.Error.profileConflict
        }
        return try WorkflowProfileJSON.encode(snapshot)
    }
}

/// Export-only adapter; fileImporter uses the capped descriptor reader above.
public struct WorkflowProfileExportDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.json] }
    public let canonicalDefinition: Data

    init(verifiedCanonicalDefinition: Data) { canonicalDefinition = verifiedCanonicalDefinition }

    public init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: canonicalDefinition)
    }
}

public struct WorkflowProfileTransferView: View {
    @ObservedObject private var model: WorkflowDocumentOpeningModel
    private let selectedProfile: WorkflowProfile?
    @State private var importing = false
    @State private var exporting = false
    @State private var exportDocument: WorkflowProfileExportDocument?

    public init(model: WorkflowDocumentOpeningModel, selectedProfile: WorkflowProfile?) {
        self.model = model
        self.selectedProfile = selectedProfile
    }

    public var body: some View {
        GroupBox("Workflow definition import/export") {
            VStack(alignment: .leading) {
                HStack {
                    Button("Import Workflow JSON…") { importing = true }
                        .disabled(model.isTransferringProfile || model.uncertainImportedProfile != nil)
                    if model.uncertainImportedProfile != nil {
                        Button("Reconcile Import") { Task { await model.reconcileProfileImport() } }
                            .disabled(model.isTransferringProfile)
                    }
                    Button("Export Selected Saved Revision…") {
                        guard let selectedProfile else { return }
                        Task {
                            if let document = await model.prepareProfileExport(selectedProfile) {
                                exportDocument = document
                                exporting = true
                            }
                        }
                    }.disabled(selectedProfile == nil || model.isTransferringProfile)
                }
                if model.isTransferringProfile { ProgressView("Transferring workflow definition…") }
                Text("Import creates a new local workflow without unattended approval. Open it with an original PDF and review before approval. Export includes identifiers and layout settings, but no PDF or approval; review before sharing.")
                    .font(.caption)
                if let status = model.profileTransferStatus { Text(status).accessibilityLabel(status) }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case let .success(url): Task { await model.importProfileDefinition(url) }
            case .failure: model.reportProfileTransferFailure()
            }
        }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json,
                      defaultFilename: "label-workflow") { result in
            switch result {
            case .success: model.reportProfileExportCompletion()
            case .failure: model.reportProfileTransferFailure()
            }
            exportDocument = nil
        }
    }
}

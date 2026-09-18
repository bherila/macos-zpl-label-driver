import Foundation

/// An allowlisted offline UI snapshot, not a log dump or compatibility report.
/// No source bytes, paths, identifiers, option values or error strings enter
/// the report. Only the user's explicit copy action publishes this text.
public struct OfflineSetupDiagnostics: Equatable, Sendable {
    public let setupAvailable: Bool
    public let setupErrorPresent: Bool
    public let scratchWarningPresent: Bool
    public let documentModelAvailable: Bool
    public let opening: Bool
    public let openingErrorPresent: Bool
    public let catalogErrorPresent: Bool
    public let importPublicationUncertain: Bool
    public let editorAvailable: Bool
    public let manualDraft: Bool
    public let savedRevision: Bool
    public let sourceReferenceAvailable: Bool
    public let exactPreviewAvailable: Bool
    public let preparingPreview: Bool
    public let editorErrorPresent: Bool

    @MainActor
    public init(documents: WorkflowDocumentOpeningModel?, setupAvailable: Bool,
                setupErrorPresent: Bool, scratchWarningPresent: Bool) {
        self.setupAvailable = setupAvailable
        self.setupErrorPresent = setupErrorPresent
        self.scratchWarningPresent = scratchWarningPresent
        documentModelAvailable = documents != nil
        opening = documents?.isOpening ?? false
        openingErrorPresent = documents?.error != nil
        catalogErrorPresent = documents?.savedWorkflowError != nil
        importPublicationUncertain = documents?.uncertainImportedProfile != nil
        let editor = documents?.editor
        editorAvailable = editor != nil
        manualDraft = editor?.isManualDraft ?? false
        savedRevision = editor?.isSaved ?? false
        sourceReferenceAvailable = editor?.sourcePreview != nil
        exactPreviewAvailable = editor?.preview != nil
        preparingPreview = editor?.isPreparingPreview ?? false
        editorErrorPresent = editor?.lastError != nil || editor?.sourcePreviewError != nil
    }

    /// Fixed vocabulary and boolean values bound output size independently of
    /// the underlying PDF, catalog, identities, exception or filesystem path.
    public var text: String {
        let fields: [(String, Bool)] = [
            ("setup_available", setupAvailable),
            ("setup_error_present", setupErrorPresent),
            ("scratch_warning_present", scratchWarningPresent),
            ("document_model_available", documentModelAvailable),
            ("opening", opening),
            ("opening_error_present", openingErrorPresent),
            ("catalog_error_present", catalogErrorPresent),
            ("import_publication_uncertain", importPublicationUncertain),
            ("editor_available", editorAvailable),
            ("manual_draft", manualDraft),
            ("saved_revision", savedRevision),
            ("source_reference_available", sourceReferenceAvailable),
            ("exact_preview_available", exactPreviewAvailable),
            ("preparing_preview", preparingPreview),
            ("editor_error_present", editorErrorPresent),
        ]
        return "offline_setup_diagnostics_version=1\n"
            + "scope=offline_ui_snapshot_only\n"
            + "installation_scheduler_hardware_acceptance=not_established_by_this_report\n"
            + fields.map { "\($0.0)=\($0.1 ? "yes" : "no")" }.joined(separator: "\n") + "\n"
    }
}

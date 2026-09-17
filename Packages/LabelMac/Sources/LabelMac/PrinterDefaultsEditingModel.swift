import Combine
import Foundation
import LabelCore
import SwiftUI

/// User-owned immutable utility defaults. No scheduler, privilege or device I/O.
@MainActor
public final class PrinterDefaultsEditingModel: ObservableObject {
    public enum Error: Swift.Error, Equatable, Sendable { case revisionOverflow, readbackMismatch }
    @Published public private(set) var setup: ReferencePrinterSetupModel { didSet { observeDraftChanges() } }
    @Published public private(set) var savedProfiles: [StoredPrinterProfile] = []
    @Published public private(set) var currentReference: ImmutableProfileReference?
    @Published public private(set) var message: String?
    public let profileID: String
    private let store: PrinterProfileStore
    private var draftChanges: AnyCancellable?

    public init(store: PrinterProfileStore, profileID: String = "gc420d-usb", initialProfile: PrinterProfile) throws {
        self.store = store
        self.profileID = profileID
        setup = ReferencePrinterSetupModel(profile: initialProfile)
        let catalog = try store.savedProfiles(id: profileID)
        savedProfiles = catalog
        if let latest = catalog.first {
            setup = ReferencePrinterSetupModel(profile: latest.profile)
            currentReference = latest.reference
        }
        observeDraftChanges()
    }

    private func observeDraftChanges() {
        draftChanges = setup.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    public func refresh() throws {
        savedProfiles = try store.savedProfiles(id: profileID)
    }

    public func reopen(_ reference: ImmutableProfileReference) throws {
        guard reference.id == profileID else { throw Error.readbackMismatch }
        let profile = try store.load(reference: reference)
        setup = ReferencePrinterSetupModel(profile: profile)
        currentReference = reference
        message = "Utility revision \(reference.revision) reopened. Installed queue defaults and printer settings are unchanged."
    }

    /// Captures effective draft controls once, publishes a fresh immutable
    /// revision, and changes the utility model only after exact readback.
    @discardableResult
    public func save() throws -> ImmutableProfileReference {
        let snapshot = setup.profile
        let controls = try setup.workflowDefaults()
        let catalog = try store.savedProfiles(id: profileID)
        let highest = max(snapshot.revision, catalog.first?.profile.revision ?? 0)
        guard highest < Int.max else { throw Error.revisionOverflow }
        let profile = try PrinterProfile(schemaVersion: max(2, snapshot.schemaVersion), revision: highest + 1,
            capabilities: snapshot.capabilities, installedHardware: snapshot.installedHardware,
            media: snapshot.media, connection: snapshot.connection,
            configuredDefaults: .init(thermalMethod: controls.thermalMethod, finishing: controls.finishing,
                printSpeedIps: controls.printSpeedIps, feedSpeedIps: controls.feedSpeedIps,
                backfeedSpeedIps: controls.backfeedSpeedIps, darkness: controls.darkness,
                tracking: controls.tracking, mediaGeometry: controls.mediaGeometry, offsets: controls.offsets))
        let reference = try store.save(id: profileID, profile: profile)
        guard try store.load(reference: reference) == profile else { throw Error.readbackMismatch }
        let refreshed = try store.savedProfiles(id: profileID)
        guard refreshed.contains(where: { $0.reference == reference && $0.profile == profile }) else {
            throw Error.readbackMismatch
        }
        savedProfiles = refreshed
        setup = ReferencePrinterSetupModel(profile: profile)
        currentReference = reference
        message = "Utility default revision \(reference.revision) saved. Existing jobs keep their bound revisions."
        return reference
    }

    public func report(_ error: Swift.Error) {
        switch error {
        case PrinterProfileStore.Error.commitUncertain:
            message = "Saving this revision could not be confirmed. Keep the draft and refresh available revisions before choosing a next step."
        case PrinterProfileStore.Error.profileConflict:
            message = "Another editor saved this revision. Refresh and reopen the desired revision before saving again."
        case Error.readbackMismatch:
            message = "Utility revision could not be verified. The current draft is retained; refresh available revisions before choosing a next step."
        case Error.revisionOverflow:
            message = "No later revision can be created for this profile."
        default:
            message = "Utility defaults could not be saved or reopened. The current draft is retained."
        }
    }
}

public struct PrinterDefaultsEditingView: View {
    @ObservedObject private var model: PrinterDefaultsEditingModel
    @State private var selectedRevision: Int?
    public init(model: PrinterDefaultsEditingModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReferencePrinterSetupView(model: model.setup)
            GroupBox("Saved utility default revisions") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.currentReference.map { "Current utility revision: \($0.revision)" } ?? "Factory reference draft")
                    Picker("Available revision", selection: $selectedRevision) {
                        Text("Choose a revision").tag(Int?.none)
                        ForEach(model.savedProfiles, id: \.reference.revision) { entry in
                            Text("Revision \(entry.reference.revision)").tag(Int?.some(entry.reference.revision))
                        }
                    }
                    HStack {
                        Button("Save Utility Defaults") { perform { _ = try model.save() } }
                            .disabled(model.setup.validationMessage != nil)
                        Button("Reopen Selected Revision") {
                            if let reference = model.savedProfiles.first(where: { $0.reference.revision == selectedRevision })?.reference {
                                perform { try model.reopen(reference) }
                            }
                        }.disabled(!model.savedProfiles.contains { $0.reference.revision == selectedRevision })
                        Button("Refresh Revisions") { perform { try model.refresh() } }
                    }
                    Text("Saved revisions reopen in this utility. Reopening replaces the current draft. These actions do not install a queue or send printer commands.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let message = model.message { Text(message).accessibilityLabel(message) }
                }
            }
        }
    }

    private func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { model.report(error) }
    }
}

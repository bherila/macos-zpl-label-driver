import Combine
import Foundation
import SwiftUI

@MainActor
public final class USBRegistryDiscoveryModel: ObservableObject {
    @Published public private(set) var snapshot: USBRegistryDiscoverySnapshot?
    @Published public private(set) var isDiscovering = false
    @Published public private(set) var status: String?
    @Published public var selectedObservationID: UUID?
    private var request: UUID?
    private let discover: @Sendable () async throws -> USBRegistryDiscoverySnapshot

    /// The observation the picker currently names, if any.
    ///
    /// Resolving the selection is not acting on it. Selection stays inert:
    /// nothing here qualifies an identity or touches a profile.
    public var selectedObservation: USBPrinterObservation? {
        guard let selectedObservationID else { return nil }
        return snapshot?.printers.first { $0.id == selectedObservationID }
    }

    public init() { discover = { try USBRegistryDiscovery.snapshot() } }
    init(discover: @escaping @Sendable () async throws -> USBRegistryDiscoverySnapshot) { self.discover = discover }

    public func refresh() async {
        let token = UUID()
        request = token
        isDiscovering = true
        snapshot = nil
        selectedObservationID = nil
        status = nil
        defer { if request == token { request = nil; isDiscovering = false } }
        let discover = self.discover
        let operation = Task.detached { try await discover() }
        do {
            let result = try await withTaskCancellationHandler(
                operation: { try await operation.value }, onCancel: { operation.cancel() })
            try Task.checkCancellation()
            guard request == token else { return }
            snapshot = result
            status = result.printers.isEmpty
                ? "No printer-class USB interfaces were exposed by this registry scan. This is not proof of physical disconnection."
                : "Printer-class USB interfaces observed. Model, stable identity and transport remain unqualified."
            if result.unreadableInterfaceClasses > 0 {
                status = String(localized: "Some USB interface metadata was unreadable. This scan cannot establish printer absence; no stable identity was qualified.")
            }
        } catch {
            guard request == token else { return }
            switch error {
            case is CancellationError: status = String(localized: "USB discovery cancelled.")
            case USBRegistryDiscovery.Error.changed: status = String(localized: "USB registry changed during discovery. Refresh before selecting an observation.")
            case USBRegistryDiscovery.Error.interfaceLimit: status = String(localized: "USB discovery exceeded its interface limit. No partial scan was accepted.")
            case USBRegistryDiscovery.Error.unreadablePrinterMetadata: status = String(localized: "Printer-class USB metadata could not be validated. No identity was qualified.")
            default: status = String(localized: "Read-only USB discovery unavailable. No identity was qualified.")
            }
        }
    }
}

public struct USBRegistryDiscoveryView: View {
    @ObservedObject private var model: USBRegistryDiscoveryModel
    /// Supplied when this picker is shown beside a setup the person may
    /// qualify against. Without it the picker stays a read-only scan.
    private let setup: ReferencePrinterSetupModel?

    public init(model: USBRegistryDiscoveryModel, setup: ReferencePrinterSetupModel? = nil) {
        self.model = model
        self.setup = setup
    }

    public var body: some View {
        GroupBox("Read-only USB discovery") {
            VStack(alignment: .leading) {
                Button("Discover USB Printer Interfaces") { Task { await model.refresh() } }
                    .disabled(model.isDiscovering)
                if model.isDiscovering { ProgressView("Reading USB registry…") }
                if let snapshot = model.snapshot, !snapshot.printers.isEmpty {
                    Picker("Session-only USB interface observation", selection: $model.selectedObservationID) {
                        Text("No observation selected").tag(UUID?.none)
                        ForEach(snapshot.printers) { observation in
                            Text(observation.interfaceLabel)
                                .tag(UUID?.some(observation.id))
                        }
                    }
                }
                if let setup = setup, let observation = model.selectedObservation {
                    // Qualification is a separate, deliberate action. Choosing
                    // a row in the picker still does nothing at all.
                    Button("Use This Device's Identity") { setup.qualifyIdentity(from: observation) }
                    Text(setup.installationReadinessMessage)
                        .accessibilityLabel(setup.installationReadinessMessage)
                }
                if let status = model.status { Text(status).accessibilityLabel(status) }
                Text("Discovery reads registry metadata only. Selection does not qualify a GC420d, save a connection, authorize installation or send printer commands. Qualifying an identity records which unit this Mac is looking at; it does not install a queue, verify delivery or confirm loaded stock. Observations can become stale after attachment changes; refresh before further validation.")
                    .font(.caption)
            }
        }
    }
}

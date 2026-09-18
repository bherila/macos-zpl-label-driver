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
                status = "Some USB interface metadata was unreadable. This scan cannot establish printer absence; no stable identity was qualified."
            }
        } catch {
            guard request == token else { return }
            switch error {
            case is CancellationError: status = "USB discovery cancelled."
            case USBRegistryDiscovery.Error.changed: status = "USB registry changed during discovery. Refresh before selecting an observation."
            case USBRegistryDiscovery.Error.interfaceLimit: status = "USB discovery exceeded its interface limit. No partial scan was accepted."
            case USBRegistryDiscovery.Error.unreadablePrinterMetadata: status = "Printer-class USB metadata could not be validated. No identity was qualified."
            default: status = "Read-only USB discovery unavailable. No identity was qualified."
            }
        }
    }
}

public struct USBRegistryDiscoveryView: View {
    @ObservedObject private var model: USBRegistryDiscoveryModel
    public init(model: USBRegistryDiscoveryModel) { self.model = model }

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
                            Text("USB VID \(observation.vendorID), PID \(observation.productID), interface \(observation.interfaceNumber)")
                                .tag(UUID?.some(observation.id))
                        }
                    }
                }
                if let status = model.status { Text(status).accessibilityLabel(status) }
                Text("Discovery reads registry metadata only. Selection does not qualify a GC420d, save a connection, authorize installation or send printer commands. Observations can become stale after attachment changes; refresh before further validation.")
                    .font(.caption)
            }
        }
    }
}

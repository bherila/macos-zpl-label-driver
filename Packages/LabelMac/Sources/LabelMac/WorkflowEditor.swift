import CoreGraphics
import Combine
import Foundation
import LabelCore
import SwiftUI

public struct WorkflowEditorRegion: Identifiable, Equatable, Sendable {
    public let id: String
    public let sourcePage: Int
    public let normalizedRect: NormalizedRect
    public let rotation: ExtractionRotation
    public let outputOrder: Int
}

@MainActor
public final class WorkflowEditorModel: ObservableObject {
    @Published public private(set) var draft: WorkflowProfileDraft
    @Published public var selectedRegionID: String?
    @Published public private(set) var preview: PreparedExtractionLabel?
    @Published public private(set) var lastError: String?
    @Published public private(set) var isSaved = false

    private let originalPDF: Data
    private let analyzedPages: [AnalyzedSourcePage]
    private let canvas: DotCanvas
    private let store: WorkflowProfileStore

    public init(
        draft: WorkflowProfileDraft,
        originalPDF: Data,
        analyzedPages: [AnalyzedSourcePage],
        canvas: DotCanvas,
        store: WorkflowProfileStore
    ) {
        self.draft = draft
        self.originalPDF = originalPDF
        self.analyzedPages = analyzedPages
        self.canvas = canvas
        self.store = store
        self.selectedRegionID = Self.regions(in: draft.profile).first?.id
    }

    public var profile: WorkflowProfile { draft.validatedProfile() }
    public var regions: [WorkflowEditorRegion] { Self.regions(in: profile) }

    public func select(_ id: String) { selectedRegionID = id }

    public func setSelectedRegionMillimeters(
        left: Double, top: Double, width: Double, height: Double
    ) throws {
        guard let selectedRegionID,
              let region = regions.first(where: { $0.id == selectedRegionID }),
              let rule = profile.pageRules.first(where: { $0.sourcePage == region.sourcePage }) else {
            throw WorkflowProfileDraft.Error.regionNotFound(selectedRegionID ?? "")
        }
        let size = rule.expectedInput.uprightPhysicalSize
        let rect = try NormalizedRect(
            x: left / size.width.value,
            y: top / size.height.value,
            width: width / size.width.value,
            height: height / size.height.value
        )
        try draft.updateRegion(id: selectedRegionID, normalizedRect: rect, rotation: region.rotation)
        preview = nil
        isSaved = false
    }

    public func setSelectedRotation(_ rotation: ExtractionRotation) throws {
        guard let selectedRegionID,
              let region = regions.first(where: { $0.id == selectedRegionID }) else {
            throw WorkflowProfileDraft.Error.regionNotFound(selectedRegionID ?? "")
        }
        try draft.updateRegion(
            id: selectedRegionID,
            normalizedRect: region.normalizedRect,
            rotation: rotation
        )
        preview = nil
        isSaved = false
    }

    public func moveSelected(by offset: Int) throws {
        guard let selectedRegionID,
              let current = regions.firstIndex(where: { $0.id == selectedRegionID }) else {
            throw WorkflowProfileDraft.Error.regionNotFound(selectedRegionID ?? "")
        }
        try draft.moveRegion(id: selectedRegionID, to: current + offset)
        preview = nil
        isSaved = false
    }

    public func refreshPreview() throws {
        guard let selectedRegionID else {
            throw WorkflowProfileDraft.Error.regionNotFound("")
        }
        let plan = try ExtractionPlanner.plan(analyzedPages: analyzedPages, profile: profile)
        guard let label = plan.outputLabels.first(where: { $0.regionID == selectedRegionID }) else {
            throw WorkflowProfileDraft.Error.regionNotFound(selectedRegionID)
        }
        preview = try QuartzPlannedExtraction.prepare(
            originalPDF: originalPDF,
            label: label,
            canvas: canvas,
            conversion: profile.monochromeConversion
        )
        lastError = nil
    }

    public func save() throws {
        try store.save(profile)
        isSaved = true
        lastError = nil
    }

    public func approveForUnattendedUse() throws {
        try store.confirmForUnattendedUse(profile)
        lastError = nil
    }

    public func reloadForCorrection(profileID: String, revision: Int) throws {
        let stored = try store.load(profileID: profileID, revision: revision)
        draft = try WorkflowProfileDraft(nextRevisionOf: stored)
        selectedRegionID = Self.regions(in: draft.profile).first?.id
        preview = nil
        isSaved = false
        lastError = nil
    }

    public func report(_ error: Swift.Error) { lastError = String(describing: error) }

    private static func regions(in profile: WorkflowProfile) -> [WorkflowEditorRegion] {
        profile.pageRules.flatMap { rule -> [WorkflowEditorRegion] in
            guard case let .extract(regions) = rule.disposition else { return [] }
            return regions.map {
                WorkflowEditorRegion(
                    id: $0.id, sourcePage: rule.sourcePage,
                    normalizedRect: $0.normalizedRect,
                    rotation: $0.rotation, outputOrder: $0.outputOrder
                )
            }
        }.sorted { $0.outputOrder < $1.outputOrder }
    }
}

public struct WorkflowEditorView: View {
    @ObservedObject private var model: WorkflowEditorModel

    public init(model: WorkflowEditorModel) { self.model = model }

    public var body: some View {
        HSplitView {
            List(model.regions, selection: $model.selectedRegionID) { region in
                Text("\(region.outputOrder + 1). \(region.id)")
                    .tag(region.id)
            }
            .frame(minWidth: 180)
            .accessibilityLabel("Label regions in output order")

            VStack(alignment: .leading, spacing: 12) {
                mediaSummary
                if let region = selectedRegion { regionControls(region) }
                previewView
                if let error = model.lastError {
                    Text(error).foregroundStyle(.red).accessibilityLabel("Editor error: \(error)")
                }
                HStack {
                    Button("Preview") { perform(model.refreshPreview) }
                        .keyboardShortcut("p", modifiers: [.command])
                    Button("Save Revision") { perform(model.save) }
                        .keyboardShortcut("s", modifiers: [.command])
                    Button("Approve for Unattended Use") { perform(model.approveForUnattendedUse) }
                        .disabled(!model.isSaved)
                }
            }
            .padding()
            .frame(minWidth: 480)
        }
    }

    private var selectedRegion: WorkflowEditorRegion? {
        model.regions.first { $0.id == model.selectedRegionID }
    }

    private var mediaSummary: some View {
        let stock = model.profile.outputStock
        return VStack(alignment: .leading) {
            Text("Input sheet geometry is configured per source page.")
            Text("Output stock: \(stock.width.value, format: .number.precision(.fractionLength(1))) × \(stock.height.value, format: .number.precision(.fractionLength(1))) mm")
        }.accessibilityElement(children: .combine)
    }

    private func regionControls(_ region: WorkflowEditorRegion) -> some View {
        let rule = model.profile.pageRules.first { $0.sourcePage == region.sourcePage }!
        let size = rule.expectedInput.uprightPhysicalSize
        return VStack(alignment: .leading) {
            Text("Region \(region.id) — source page \(region.sourcePage)").font(.headline)
            HStack {
                measurementField("Left (mm)", value: region.normalizedRect.x * size.width.value) { left in
                    try update(region, left: left)
                }
                measurementField("Top (mm)", value: region.normalizedRect.y * size.height.value) { top in
                    try update(region, top: top)
                }
                measurementField("Width (mm)", value: region.normalizedRect.width * size.width.value) { width in
                    try update(region, width: width)
                }
                measurementField("Height (mm)", value: region.normalizedRect.height * size.height.value) { height in
                    try update(region, height: height)
                }
            }
            Picker("Rotation", selection: Binding(
                get: { region.rotation },
                set: { value in perform { try model.setSelectedRotation(value) } }
            )) {
                Text("0°").tag(ExtractionRotation.degrees0)
                Text("90°").tag(ExtractionRotation.degrees90)
                Text("180°").tag(ExtractionRotation.degrees180)
                Text("270°").tag(ExtractionRotation.degrees270)
            }.pickerStyle(.segmented)
            HStack {
                Button("Move Earlier") { perform { try model.moveSelected(by: -1) } }
                    .keyboardShortcut(.upArrow, modifiers: [.command])
                    .disabled(region.outputOrder == 0)
                Button("Move Later") { perform { try model.moveSelected(by: 1) } }
                    .keyboardShortcut(.downArrow, modifiers: [.command])
                    .disabled(region.outputOrder == model.regions.count - 1)
            }
        }
    }

    private var previewView: some View {
        Group {
            if let bitmap = model.preview?.bitmap, let image = Self.image(bitmap) {
                Image(image, scale: 1, label: Text("Exact packed label preview"))
                    .resizable().interpolation(.none).scaledToFit()
            } else {
                ContentUnavailableView("Preview not generated", systemImage: "doc.viewfinder")
            }
        }.frame(maxWidth: .infinity, minHeight: 240)
    }

    private func measurementField(
        _ title: String, value: Double, update: @escaping (Double) throws -> Void
    ) -> some View {
        TextField(title, value: Binding(
            get: { value },
            set: { newValue in perform { try update(newValue) } }
        ), format: .number.precision(.fractionLength(0...2)))
        .textFieldStyle(.roundedBorder)
        .accessibilityLabel(title)
    }

    private func update(
        _ region: WorkflowEditorRegion,
        left: Double? = nil, top: Double? = nil,
        width: Double? = nil, height: Double? = nil
    ) throws {
        let rule = model.profile.pageRules.first { $0.sourcePage == region.sourcePage }!
        let size = rule.expectedInput.uprightPhysicalSize
        try model.setSelectedRegionMillimeters(
            left: left ?? region.normalizedRect.x * size.width.value,
            top: top ?? region.normalizedRect.y * size.height.value,
            width: width ?? region.normalizedRect.width * size.width.value,
            height: height ?? region.normalizedRect.height * size.height.value
        )
    }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { model.report(error) }
    }

    private static func image(_ bitmap: MonochromeBitmap) -> CGImage? {
        let preview = bitmap.grayscalePreview()
        guard let provider = CGDataProvider(data: Data(preview.pixels) as CFData) else { return nil }
        return CGImage(
            width: preview.width, height: preview.height,
            bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: preview.width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

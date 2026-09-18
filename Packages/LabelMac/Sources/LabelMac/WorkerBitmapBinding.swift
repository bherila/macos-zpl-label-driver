import Foundation
import LabelCore

/// Both render parents accept only the canonical packed bitmap actually encoded
/// into the diagnostic graphics envelope. This grants no device/state authority.
enum WorkerBitmapBinding {
    enum Error: Swift.Error { case invalidBinding }

    static func validate(_ output: OfflineRenderWorkerOutput,
                         maximumPackedBytes: Int = OfflineRenderWorkerProcess.maximumPreviewBytes) throws -> MonochromeBitmap {
        let result = output.result
        let encoder = try ZPLGraphicEncoder()
        guard result.schemaVersion == 1,
              (1...encoder.maxDimensionDots).contains(result.widthDots),
              (1...encoder.maxDimensionDots).contains(result.heightDots),
              output.zpl.count == result.zplBytes,
              output.previewPBM.count == result.previewBytes,
              output.zpl.count <= OfflineRenderWorkerProcess.maximumZPLBytes,
              output.previewPBM.count <= OfflineRenderWorkerProcess.maximumPreviewBytes else {
            throw Error.invalidBinding
        }
        let layout = try BitmapLayout(width: result.widthDots, height: result.heightDots,
                                      maxByteCount: maximumPackedBytes)
        let header = Data("P4\n\(result.widthDots) \(result.heightDots)\n".utf8)
        guard output.previewPBM.starts(with: header),
              output.previewPBM.count - header.count == layout.byteCount else {
            throw Error.invalidBinding
        }
        let bitmap = try MonochromeBitmap(width: layout.width, height: layout.height,
            bytes: Array(output.previewPBM.dropFirst(header.count)), maxByteCount: maximumPackedBytes)
        guard try encoder.diagnosticFormat(bitmap) == output.zpl else { throw Error.invalidBinding }
        return bitmap
    }
}

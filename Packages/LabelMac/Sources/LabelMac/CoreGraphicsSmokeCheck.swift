import CoreGraphics
import LabelCore

/// An inert SDK/runtime smoke check, not PDF rendering or printer support.
public enum CoreGraphicsSmokeCheck {
    public enum Failure: Error {
        case contextUnavailable
        case dataUnavailable
        case unexpectedPixel
    }

    /// Allocates a one-pixel grayscale image, paints it white, and reads it back.
    public static func run() throws -> UInt8 {
        let packed = try BitmapLayout(width: 1, height: 1)
        guard let context = CGContext(
            data: nil,
            width: packed.width,
            height: packed.height,
            bitsPerComponent: 8,
            bytesPerRow: 1,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw Failure.contextUnavailable
        }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let data = context.data else {
            throw Failure.dataUnavailable
        }
        let pixel = data.load(as: UInt8.self)
        guard pixel == 255 else {
            throw Failure.unexpectedPixel
        }
        return pixel
    }
}

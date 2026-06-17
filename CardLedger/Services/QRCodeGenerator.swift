import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

/// Renders a crisp QR image for a card's short code. The payload is a deep link so a
/// future scan can route straight to the card: `cardledger://card/<shortCode>`.
enum QRCodeGenerator {
    private static let context = CIContext()

    static func payload(for shortCode: String) -> String {
        "cardledger://card/\(shortCode)"
    }

    static func image(for shortCode: String, scale: CGFloat = 10) -> Image? {
        image(fromString: payload(for: shortCode), scale: scale)
    }

    /// Generate a QR from any string (e.g. a server URL).
    static func image(fromString string: String, scale: CGFloat = 10) -> Image? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return Image(decorative: cg, scale: 1, orientation: .up)
            .interpolation(.none)
    }

    /// A `UIImage` QR for drawing into a PDF / print context (high-res, crisp).
    static func uiImage(for shortCode: String, scale: CGFloat = 18) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload(for: shortCode).utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let transformed = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

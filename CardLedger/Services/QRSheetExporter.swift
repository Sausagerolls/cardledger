import UIKit

/// Lays out card QR codes onto A4 pages for printing — 12 per page (3 columns × 4 rows),
/// each QR roughly trading-card width (~53 mm) with the short code + name beneath and a
/// faint cut border. Output is a PDF suitable for AirPrint, Files, or email.
enum QRSheetExporter {
    // A4 at 72 pt/inch.
    private static let pageW: CGFloat = 595.2
    private static let pageH: CGFloat = 841.8
    private static let cols = 3
    private static let rows = 4
    private static var perPage: Int { cols * rows }   // 12

    static func makePDF(for cards: [Card]) throws -> URL {
        let bounds = CGRect(x: 0, y: 0, width: pageW, height: pageH)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "CardLedger QR Sheet",
            kCGPDFContextCreator as String: "CardLedger"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)

        let margin: CGFloat = 28
        let gutter: CGFloat = 12
        let cellW = (pageW - 2 * margin - CGFloat(cols - 1) * gutter) / CGFloat(cols)
        let cellH = (pageH - 2 * margin - CGFloat(rows - 1) * gutter) / CGFloat(rows)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CardLedger-QR-Sheet.pdf")
        try renderer.writePDF(to: url) { ctx in
            for (index, card) in cards.enumerated() {
                let slot = index % perPage
                if slot == 0 { ctx.beginPage() }
                let row = slot / cols
                let col = slot % cols
                let x = margin + CGFloat(col) * (cellW + gutter)
                let y = margin + CGFloat(row) * (cellH + gutter)
                drawCell(card, in: CGRect(x: x, y: y, width: cellW, height: cellH), ctx: ctx)
            }
        }
        return url
    }

    private static func drawCell(_ card: Card, in rect: CGRect, ctx: UIGraphicsPDFRendererContext) {
        let cg = ctx.cgContext

        // Faint cut border.
        cg.setStrokeColor(UIColor(white: 0.8, alpha: 1).cgColor)
        cg.setLineWidth(0.5)
        cg.stroke(rect.insetBy(dx: 2, dy: 2))

        let labelH: CGFloat = 32
        let qrSide = min(rect.width - 18, rect.height - labelH - 10)
        let qrRect = CGRect(x: rect.midX - qrSide / 2, y: rect.minY + 8, width: qrSide, height: qrSide)

        cg.interpolationQuality = .none   // keep QR modules crisp
        QRCodeGenerator.uiImage(for: card.shortCode)?.draw(in: qrRect)

        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byTruncatingTail

        let codeAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .bold),
            .paragraphStyle: para, .foregroundColor: UIColor.black
        ]
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8),
            .paragraphStyle: para, .foregroundColor: UIColor.darkGray
        ]

        let codeRect = CGRect(x: rect.minX + 4, y: qrRect.maxY + 2, width: rect.width - 8, height: 14)
        let nameRect = CGRect(x: rect.minX + 4, y: qrRect.maxY + 16, width: rect.width - 8, height: 12)
        (card.shortCode as NSString).draw(in: codeRect, withAttributes: codeAttrs)
        let name = card.name.isEmpty ? card.gameSystem?.name ?? "" : card.name
        (name as NSString).draw(in: nameRect, withAttributes: nameAttrs)
    }
}

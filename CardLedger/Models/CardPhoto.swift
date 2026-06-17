import Foundation
import SwiftData

/// A single photo attached to a card. Image bytes use `.externalStorage` so large
/// blobs live on disk (and sync through CloudKit) rather than bloating the store row.
@Model
final class CardPhoto {
    @Attribute(.externalStorage) var imageData: Data = Data()
    var sortIndex: Int = 0
    var createdAt: Date = Date.distantPast

    var card: Card?

    init(imageData: Data, sortIndex: Int = 0) {
        self.imageData = imageData
        self.sortIndex = sortIndex
        self.createdAt = Date()
    }
}

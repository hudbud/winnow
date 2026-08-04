import Foundation
import SwiftData

/// A user-assigned rating for a single photo library asset.
/// Absence of a row for an asset means "unrated" — distinct from an explicit rating of 0 (discarded).
@Model
final class PhotoRating {
    @Attribute(.unique) var assetIdentifier: String
    var rating: Int
    var updatedAt: Date

    init(assetIdentifier: String, rating: Int) {
        self.assetIdentifier = assetIdentifier
        self.rating = rating
        self.updatedAt = .now
    }
}

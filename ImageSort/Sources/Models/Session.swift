import Foundation
import SwiftData

/// Not derived by scanning the album's photos (that requires walking every asset
/// in it, which is exactly the PhotoKit enumeration that made the picker slow) —
/// recorded as a side effect of actually swiping, on the Session row that already
/// exists per album. Reading it is a plain local field, no PhotoKit involved.
enum AlbumSortStatus: Int, Codable {
    case notStarted = 0, partial = 1, complete = 2
}

/// Culling progress for one album. Keyed by collection identifier so re-selecting
/// the same album resumes where you left off.
@Model
final class Session {
    @Attribute(.unique) var collectionIdentifier: String
    var collectionTitle: String
    var currentPass: Int
    private var sortStatusRaw: Int
    var createdAt: Date
    var updatedAt: Date

    var sortStatus: AlbumSortStatus {
        get { AlbumSortStatus(rawValue: sortStatusRaw) ?? .notStarted }
        set { sortStatusRaw = newValue.rawValue }
    }

    init(collectionIdentifier: String, collectionTitle: String) {
        self.collectionIdentifier = collectionIdentifier
        self.collectionTitle = collectionTitle
        self.currentPass = 0
        self.sortStatusRaw = AlbumSortStatus.notStarted.rawValue
        self.createdAt = .now
        self.updatedAt = .now
    }

    func advanceToNextPass() {
        currentPass += 1
        updatedAt = .now
    }
}

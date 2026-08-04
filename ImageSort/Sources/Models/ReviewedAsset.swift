import Foundation
import SwiftData

/// One row per asset swiped during a session's current pass. Replaces a `[String]`
/// array on `Session` — appending to that array made SwiftData re-serialize the
/// entire reviewed list on every single swipe, which got expensive deep into a
/// large pass. A row insert/delete here is O(1) regardless of pass size.
@Model
final class ReviewedAsset {
    var sessionIdentifier: String
    var pass: Int
    var assetIdentifier: String

    init(sessionIdentifier: String, pass: Int, assetIdentifier: String) {
        self.sessionIdentifier = sessionIdentifier
        self.pass = pass
        self.assetIdentifier = assetIdentifier
    }
}

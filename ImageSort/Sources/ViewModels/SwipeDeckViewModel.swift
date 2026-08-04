import Foundation
import Photos
import SwiftData
import SwiftUI

enum SwipeDirection {
    case keep   // right
    case pass   // left
}

/// Drives one pass (N) over an album's assets.
///
/// Pass semantics (see PLAN.md — do not change without re-reading it):
/// - Queue for pass N = every asset with effective rating >= N, not yet reviewed this pass.
///   Effective rating treats "unrated" as 0, so pass 0 also picks up never-rated assets.
/// - Swipe right (keep): rating = max(current, N + 1). Never demotes, never double-promotes.
/// - Swipe left (pass): rating stays unchanged if already > N, otherwise becomes N.
/// - Photos already above N flow through the deck but are "locked" — the swipe is decorative.
@Observable
final class SwipeDeckViewModel {
    private(set) var session: Session
    let allAssets: [PHAsset]
    private let library: PhotoLibraryService
    private let context: ModelContext

    /// Kept in sync via `didSet` so membership checks (`canNavigateBack`) are O(1)
    /// instead of a linear scan repeated on every drag-frame render.
    private(set) var queue: [PHAsset] = [] {
        didSet { queueIdentifiers = Set(queue.map(\.localIdentifier)) }
    }
    private var queueIdentifiers: Set<String> = []

    private(set) var undoStack: [UndoEntry] = []
    var isPassComplete = false

    struct UndoEntry {
        let assetIdentifier: String
        let previousRating: Int?   // nil means the asset had no PhotoRating row before this swipe
        let wasAlreadyReviewed: Bool
    }

    let pass: Int

    /// In-memory mirror of this album's `PhotoRating` rows, keyed by asset identifier.
    /// Loaded once so rating reads are dictionary lookups instead of a SwiftData fetch
    /// per call — `storedRating`/`effectiveRating` are read from the view body dozens
    /// of times per frame while dragging.
    private var ratingCache: [String: Int] = [:]

    /// In-memory mirror of this session/pass's `ReviewedAsset` rows.
    private var reviewedCache: Set<String> = []

    /// Cards currently registered with `PHCachingImageManager`, so `prefetch()` can stop
    /// caching ones that fell behind instead of only ever adding more as the deck advances.
    private var cachedAssets: [PHAsset] = []

    init(session: Session, allAssets: [PHAsset], library: PhotoLibraryService, context: ModelContext) {
        self.session = session
        self.allAssets = allAssets
        self.library = library
        self.context = context
        self.pass = session.currentPass
        loadRatingCache()
        loadReviewedCache()
        rebuildQueue()
        prefetch()
    }

    deinit {
        library.stopCachingAll()
    }

    var topAsset: PHAsset? { queue.first }
    var upcomingAssets: [PHAsset] { Array(queue.dropFirst().prefix(2)) }
    var remainingCount: Int { queue.count }
    var totalInPass: Int { totalInPassCount }
    private var totalInPassCount = 0

    // MARK: - Queue construction

    private func rebuildQueue() {
        let filtered = allAssets.filter { asset in
            effectiveRating(asset.localIdentifier) >= pass && !reviewedCache.contains(asset.localIdentifier)
        }
        queue = filtered
        totalInPassCount = allAssets.filter { effectiveRating($0.localIdentifier) >= pass }.count
        isPassComplete = queue.isEmpty
    }

    func effectiveRating(_ assetIdentifier: String) -> Int {
        ratingCache[assetIdentifier] ?? 0
    }

    /// nil distinguishes "no row" (unrated) from an explicit 0.
    func storedRating(_ assetIdentifier: String) -> Int? {
        ratingCache[assetIdentifier]
    }

    private func loadRatingCache() {
        let identifiers = Set(allAssets.map(\.localIdentifier))
        let descriptor = FetchDescriptor<PhotoRating>(
            predicate: #Predicate { identifiers.contains($0.assetIdentifier) }
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        ratingCache = Dictionary(uniqueKeysWithValues: rows.map { ($0.assetIdentifier, $0.rating) })
    }

    private func loadReviewedCache() {
        let sessionID = session.collectionIdentifier
        let currentPass = pass
        let descriptor = FetchDescriptor<ReviewedAsset>(
            predicate: #Predicate { $0.sessionIdentifier == sessionID && $0.pass == currentPass }
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        reviewedCache = Set(rows.map(\.assetIdentifier))
    }

    // MARK: - Swiping

    func commit(_ direction: SwipeDirection, on asset: PHAsset) {
        guard topAsset?.localIdentifier == asset.localIdentifier else { return }
        let identifier = asset.localIdentifier
        let previousRating = storedRating(identifier)
        let current = previousRating ?? 0

        let newRating: Int
        switch direction {
        case .keep:
            newRating = max(current, pass + 1)
        case .pass:
            newRating = current > pass ? current : pass
        }

        undoStack.append(UndoEntry(assetIdentifier: identifier, previousRating: previousRating, wasAlreadyReviewed: false))

        setRating(identifier, to: newRating)
        markReviewed(identifier)
        queue.removeFirst()
        isPassComplete = queue.isEmpty
        syncSortStatus()
        prefetch()
    }

    /// Directly sets the top card's rating (via the badge picker) instead of the
    /// clamped swipe promotion — an explicit override, so unlike `commit` it can
    /// jump straight to any tier or demote, in either direction.
    func setManualRating(_ rating: Int, for asset: PHAsset) {
        guard topAsset?.localIdentifier == asset.localIdentifier else { return }
        let identifier = asset.localIdentifier
        let previousRating = storedRating(identifier)

        undoStack.append(UndoEntry(assetIdentifier: identifier, previousRating: previousRating, wasAlreadyReviewed: false))

        setRating(identifier, to: rating)
        markReviewed(identifier)
        queue.removeFirst()
        isPassComplete = queue.isEmpty
        syncSortStatus()
        prefetch()
    }

    /// Records the album-level status as a side effect of an actual decision, rather
    /// than deriving it later by scanning the album's photos. Only pass 0 completion
    /// means "fully sorted" — later refinement passes don't change this coarse signal.
    private func syncSortStatus() {
        guard pass == 0 else {
            if session.sortStatus == .notStarted { session.sortStatus = .partial }
            return
        }
        session.sortStatus = isPassComplete ? .complete : .partial
    }

    /// Assets skipped this launch, most recent last — lets `navigateBack` return to
    /// one without touching any rating, unlike `undoLastSwipe` which reverts a decision.
    private(set) var skipHistory: [String] = []

    /// True only if some skipped card is still actually in the queue to return to —
    /// entries for cards since decided (and removed from the queue) don't count.
    var canNavigateBack: Bool {
        skipHistory.contains { queueIdentifiers.contains($0) }
    }

    /// Defers the top card to the end of this launch's in-memory queue without deciding it.
    func skip() {
        guard !queue.isEmpty else { return }
        let asset = queue.removeFirst()
        skipHistory.append(asset.localIdentifier)
        queue.append(asset)
        prefetch()
    }

    /// Pure navigation, not a data change: brings the most recently skipped card back
    /// to the front so you can look at it again. Cards since decided (and removed from
    /// the queue) are skipped over automatically — that's what undo is for, not this.
    func navigateBack() {
        while let identifier = skipHistory.popLast() {
            guard let index = queue.firstIndex(where: { $0.localIdentifier == identifier }) else { continue }
            let asset = queue.remove(at: index)
            queue.insert(asset, at: 0)
            isPassComplete = false
            prefetch()
            return
        }
    }

    func undoLastSwipe() {
        guard let entry = undoStack.popLast() else { return }
        guard let asset = allAssets.first(where: { $0.localIdentifier == entry.assetIdentifier }) else { return }

        if let previousRating = entry.previousRating {
            setRating(entry.assetIdentifier, to: previousRating)
        } else {
            deleteRating(entry.assetIdentifier)
        }
        unmarkReviewed(entry.assetIdentifier)
        queue.insert(asset, at: 0)
        isPassComplete = false
        syncSortStatus()
        prefetch()
    }

    var canUndo: Bool { !undoStack.isEmpty }

    /// Advances the session to the next pass and prunes this pass's `ReviewedAsset`
    /// rows. They're scoped by pass number, so a fresh queue rebuild would ignore
    /// them anyway — this just keeps the table from growing unbounded over the
    /// life of a long-lived album.
    func advanceToNextPass() {
        let sessionID = session.collectionIdentifier
        let completedPass = pass
        let descriptor = FetchDescriptor<ReviewedAsset>(
            predicate: #Predicate { $0.sessionIdentifier == sessionID && $0.pass == completedPass }
        )
        if let rows = try? context.fetch(descriptor) {
            for row in rows { context.delete(row) }
        }
        session.advanceToNextPass()
    }

    // MARK: - Review screen support

    /// Assets that ended this pass promoted above N (i.e. the "kept" set so far).
    var survivors: [PHAsset] {
        allAssets.filter { effectiveRating($0.localIdentifier) >= pass + 1 }
    }

    /// Toggle a survivor across the N / N+1 boundary from the review grid.
    func toggleSurvivor(_ asset: PHAsset) {
        let identifier = asset.localIdentifier
        let current = effectiveRating(identifier)
        if current >= pass + 1 {
            setRating(identifier, to: pass)
        } else {
            setRating(identifier, to: pass + 1)
        }
    }

    // MARK: - Persistence helpers

    private func setRating(_ assetIdentifier: String, to rating: Int) {
        ratingCache[assetIdentifier] = rating
        var descriptor = FetchDescriptor<PhotoRating>(
            predicate: #Predicate { $0.assetIdentifier == assetIdentifier }
        )
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.rating = rating
            existing.updatedAt = .now
        } else {
            context.insert(PhotoRating(assetIdentifier: assetIdentifier, rating: rating))
        }
    }

    private func deleteRating(_ assetIdentifier: String) {
        ratingCache.removeValue(forKey: assetIdentifier)
        var descriptor = FetchDescriptor<PhotoRating>(
            predicate: #Predicate { $0.assetIdentifier == assetIdentifier }
        )
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            context.delete(existing)
        }
    }

    private func markReviewed(_ assetIdentifier: String) {
        guard !reviewedCache.contains(assetIdentifier) else { return }
        reviewedCache.insert(assetIdentifier)
        context.insert(ReviewedAsset(sessionIdentifier: session.collectionIdentifier, pass: pass, assetIdentifier: assetIdentifier))
    }

    private func unmarkReviewed(_ assetIdentifier: String) {
        guard reviewedCache.remove(assetIdentifier) != nil else { return }
        let sessionID = session.collectionIdentifier
        let currentPass = pass
        var descriptor = FetchDescriptor<ReviewedAsset>(
            predicate: #Predicate { $0.sessionIdentifier == sessionID && $0.pass == currentPass && $0.assetIdentifier == assetIdentifier }
        )
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            context.delete(existing)
        }
    }

    // MARK: - Prefetch

    private func prefetch() {
        let ahead = Array(queue.prefix(10))
        let aheadIdentifiers = Set(ahead.map(\.localIdentifier))
        let noLongerNeeded = cachedAssets.filter { !aheadIdentifiers.contains($0.localIdentifier) }
        if !noLongerNeeded.isEmpty {
            library.stopCaching(noLongerNeeded, targetSize: PhotoLibraryService.cardTargetSize)
        }
        library.startCaching(ahead, targetSize: PhotoLibraryService.cardTargetSize)
        cachedAssets = ahead
    }
}

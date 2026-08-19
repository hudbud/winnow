import Foundation
import Photos
import SwiftData

@Observable
@MainActor
final class AlbumPickerViewModel {
    private(set) var albums: [AlbumInfo] = []
    private(set) var isLoading = false

    /// One bulk fetch instead of a FetchDescriptor per row — both the sorted-status
    /// badge and "Pass N in progress" read from this.
    private var sessionsByAlbumID: [String: Session] = [:]

    private let library: PhotoLibraryService

    init(library: PhotoLibraryService = .shared) {
        self.library = library
    }

    /// Runs the PhotoKit fetch off the main thread — with many albums, even the
    /// O(1)-per-album `fetchAlbums()` adds up, and this must never block the UI
    /// thread the way the old per-asset enumeration did. Status is no longer
    /// derived from PhotoKit at all (see `Session.sortStatus`), so this is now
    /// the only PhotoKit work the picker does.
    func loadAlbums(context: ModelContext) {
        isLoading = true
        Task {
            let fetched = await Task.detached(priority: .userInitiated) {
                PhotoLibraryService.shared.fetchAlbums()
            }.value
            // Back on main actor for SwiftUI state mutation and ModelContext access
            await MainActor.run {
                albums = fetched
                let sessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
                sessionsByAlbumID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.collectionIdentifier, $0) })
                isLoading = false
            }
        }
    }

    func status(for album: AlbumInfo) -> AlbumSortStatus {
        sessionsByAlbumID[album.id]?.sortStatus ?? .notStarted
    }

    /// Finds or creates the Session for an album, keyed by collection identifier so
    /// re-selecting the same album resumes existing progress.
    func session(for album: AlbumInfo, context: ModelContext) -> Session {
        if let existing = sessionsByAlbumID[album.id] {
            return existing
        }
        let session = Session(collectionIdentifier: album.id, collectionTitle: album.title)
        context.insert(session)
        sessionsByAlbumID[album.id] = session
        return session
    }

    func existingSession(for album: AlbumInfo, context: ModelContext) -> Session? {
        sessionsByAlbumID[album.id]
    }
}

import AVFoundation
import Photos
import UIKit

struct AlbumInfo: Identifiable, Hashable {
    let collection: PHAssetCollection
    let count: Int
    let videoCount: Int
    let coverAsset: PHAsset?
    let isShared: Bool
    /// Capture date of the newest asset in the album — used for "Newest" sort.
    let sortDate: Date

    var id: String { collection.localIdentifier }
    var title: String { collection.localizedTitle ?? "Untitled Album" }
    var photoCount: Int { count - videoCount }
}

/// Thin wrapper around PhotoKit. The photo library is only ever mutated by the
/// explicit methods here (create/update album, favorite, delete) — never as a
/// side effect of browsing or rating.
final class PhotoLibraryService {
    static let shared = PhotoLibraryService()

    let cachingManager = PHCachingImageManager()

    /// Single size used for every deck-card request (prefetch, degraded, and full-quality).
    /// `PHCachingImageManager` keys its cache by target size, so prefetching and displaying
    /// at different sizes never hits the cache at all — this constant is what makes the
    /// prefetch in `SwipeDeckViewModel` actually pay off. Full screen bounds is a superset
    /// of the card's real (slightly padded) size, which keeps this single value valid
    /// regardless of exact layout.
    static let cardTargetSize: CGSize = {
        let bounds = UIScreen.main.bounds
        let scale = UIScreen.main.scale
        return CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }()

    func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    var currentAuthorizationStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    // MARK: - Fetching

    func fetchAlbums() -> [AlbumInfo] {
        var infos: [AlbumInfo] = []

        func makeInfo(_ collection: PHAssetCollection, isShared: Bool) -> AlbumInfo? {
            // .count/.firstObject/.lastObject are O(1) — no enumeration. A separate
            // count-only fetch for videos keeps this O(1) too, instead of walking
            // every asset in the album (which was minutes-long on a real library).
            let result = PHAsset.fetchAssets(in: collection, options: Self.assetFetchOptions())
            guard result.count > 0 else { return nil }

            let videoOptions = PHFetchOptions()
            videoOptions.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
            let videoCount = PHAsset.fetchAssets(in: collection, options: videoOptions).count

            return AlbumInfo(
                collection: collection,
                count: result.count,
                videoCount: videoCount,
                coverAsset: result.firstObject,
                isShared: isShared,
                sortDate: result.lastObject?.creationDate ?? .distantPast
            )
        }

        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        userAlbums.enumerateObjects { collection, _, _ in
            if let info = makeInfo(collection, isShared: collection.assetCollectionSubtype == .albumCloudShared) {
                infos.append(info)
            }
        }

        let smartAlbums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil)
        smartAlbums.enumerateObjects { collection, _, _ in
            switch collection.assetCollectionSubtype {
            case .smartAlbumUserLibrary, .smartAlbumFavorites, .smartAlbumRecentlyAdded, .smartAlbumPanoramas, .smartAlbumScreenshots:
                if let info = makeInfo(collection, isShared: false) {
                    infos.append(info)
                }
            default:
                break
            }
        }

        return infos.sorted { $0.count > $1.count }
    }

    func album(withIdentifier identifier: String) -> PHAssetCollection? {
        PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [identifier], options: nil).firstObject
    }

    /// All assets in a collection, ordered by capture date (oldest first).
    func fetchAssets(in collection: PHAssetCollection) -> [PHAsset] {
        let result = PHAsset.fetchAssets(in: collection, options: Self.assetFetchOptions())
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    func asset(withIdentifier identifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
    }

    private static func assetFetchOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.predicate = NSPredicate(format: "mediaType == %d OR mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        return options
    }

    // MARK: - Caching / image loading

    func startCaching(_ assets: [PHAsset], targetSize: CGSize) {
        cachingManager.startCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFit, options: nil)
    }

    func stopCaching(_ assets: [PHAsset], targetSize: CGSize) {
        cachingManager.stopCachingImages(for: assets, targetSize: targetSize, contentMode: .aspectFit, options: nil)
    }

    /// Called when leaving the deck — otherwise the cache set only ever grows for the
    /// life of the view model, since per-swipe caching only ever adds ahead of position.
    func stopCachingAll() {
        cachingManager.stopCachingImagesForAllAssets()
    }

    /// Loads a display image, first delivering a fast degraded result then the full-quality one.
    /// Requests `.aspectFit` — the swipe deck shows the whole photo, uncropped, so we
    /// shouldn't fetch a pre-cropped `.aspectFill` variant that would throw content away.
    func loadImage(for asset: PHAsset, targetSize: CGSize, onUpdate: @escaping (UIImage) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        cachingManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options) { image, _ in
            if let image {
                DispatchQueue.main.async { onUpdate(image) }
            }
        }
    }

    /// Loads a cropped square thumbnail (album covers, review grid), delivering a fast
    /// degraded result first then the full-quality one — the review grid can hold
    /// hundreds of survivors, and waiting for high-quality-only made it feel stalled.
    /// `.resizeMode = .exact` forces PhotoKit to actually conform to `targetSize`/
    /// `.aspectFill` rather than the "close enough" sizing its faster resize modes return.
    func loadThumbnail(for asset: PHAsset, targetSize: CGSize, onUpdate: @escaping (UIImage) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false
        cachingManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options) { image, _ in
            if let image {
                DispatchQueue.main.async { onUpdate(image) }
            }
        }
    }

    func loadLivePhoto(for asset: PHAsset, targetSize: CGSize) async -> PHLivePhoto? {
        await withCheckedContinuation { continuation in
            let options = PHLivePhotoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            var didResume = false
            PHImageManager.default().requestLivePhoto(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options) { livePhoto, info in
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded, !didResume {
                    didResume = true
                    continuation.resume(returning: livePhoto)
                }
            }
        }
    }

    func loadPlayerItem(for asset: PHAsset) async -> AVPlayerItem? {
        await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .automatic
            options.isNetworkAccessAllowed = true
            var didResume = false
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: item)
            }
        }
    }

    // MARK: - Mutations (the only place the real library changes)

    @discardableResult
    func createAlbum(title: String, assets: [PHAsset]) async throws -> PHAssetCollection {
        var placeholder: PHObjectPlaceholder?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            request.addAssets(assets as NSArray)
            placeholder = request.placeholderForCreatedAssetCollection
        }
        guard let identifier = placeholder?.localIdentifier,
              let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [identifier], options: nil).firstObject else {
            throw PhotoLibraryError.albumCreationFailed
        }
        return collection
    }

    /// Makes an existing album's contents match `assets` exactly (adds missing, removes extras).
    func syncAlbum(_ collection: PHAssetCollection, toMatch assets: [PHAsset]) async throws {
        let existing = Set(fetchAssets(in: collection).map(\.localIdentifier))
        let desired = Set(assets.map(\.localIdentifier))
        let toAdd = assets.filter { !existing.contains($0.localIdentifier) }
        let toRemoveIdentifiers = existing.subtracting(desired)
        guard !toAdd.isEmpty || !toRemoveIdentifiers.isEmpty else { return }

        try await PHPhotoLibrary.shared().performChanges {
            guard let request = PHAssetCollectionChangeRequest(for: collection) else { return }
            if !toAdd.isEmpty {
                request.addAssets(toAdd as NSArray)
            }
            if !toRemoveIdentifiers.isEmpty {
                let toRemove = PHAsset.fetchAssets(withLocalIdentifiers: Array(toRemoveIdentifiers), options: nil)
                request.removeAssets(toRemove)
            }
        }
    }

    func setFavorite(_ assets: [PHAsset], favorite: Bool) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            for asset in assets {
                let request = PHAssetChangeRequest(for: asset)
                request.isFavorite = favorite
            }
        }
    }

    func deleteAssets(_ assets: [PHAsset]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
    }
}

enum PhotoLibraryError: Error {
    case albumCreationFailed
}

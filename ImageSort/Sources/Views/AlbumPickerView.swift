import Photos
import SwiftData
import SwiftUI

private enum AlbumFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case mine = "My Albums"
    case shared = "Shared"
    var id: String { rawValue }
}

private enum AlbumSortOption: String, CaseIterable, Identifiable {
    case name = "Name"
    case newest = "Newest"
    case size = "Size"
    case status = "Sorted Status"
    var id: String { rawValue }
}

private struct PendingDeck: Identifiable, Hashable {
    let album: AlbumInfo
    let assets: [PHAsset]
    var id: String { album.id }

    // PHAsset isn't Hashable, so identity is keyed on the album id alone —
    // there's only ever one pending deck for a given album at a time.
    static func == (lhs: PendingDeck, rhs: PendingDeck) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct AlbumPickerView: View {
    @Environment(\.modelContext) private var context
    @State private var viewModel = AlbumPickerViewModel()
    @State private var pendingDeck: PendingDeck?
    @State private var loadingAlbumID: String?
    @State private var filter: AlbumFilter = .all
    @State private var sortOption: AlbumSortOption = .name

    private var displayedAlbums: [AlbumInfo] {
        var result = viewModel.albums
        switch filter {
        case .all: break
        case .mine: result = result.filter { !$0.isShared }
        case .shared: result = result.filter { $0.isShared }
        }
        switch sortOption {
        case .name: result.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .newest: result.sort { $0.sortDate > $1.sortDate }
        case .size: result.sort { $0.count > $1.count }
        case .status:
            result.sort { a, b in
                let statusA = viewModel.status(for: a)
                let statusB = viewModel.status(for: b)
                if statusA != statusB { return statusA.rawValue < statusB.rawValue }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView().tint(.white)
                } else if viewModel.albums.isEmpty {
                    ContentUnavailableView("No Albums Found", systemImage: "photo.stack", description: Text("Add photos to an album in the Photos app first."))
                } else {
                    VStack(spacing: 0) {
                        filterBar
                        List(displayedAlbums) { album in
                            AlbumRow(
                                album: album,
                                existingSession: viewModel.existingSession(for: album, context: context),
                                viewModel: viewModel,
                                isOpening: loadingAlbumID == album.id
                            )
                                .contentShape(Rectangle())
                                .onTapGesture { openAlbum(album) }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("Choose an Album")
            .navigationDestination(item: $pendingDeck) { pending in
                SwipeDeckView(session: viewModel.session(for: pending.album, context: context), allAssets: pending.assets, context: context)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { viewModel.loadAlbums(context: context) }
    }

    /// Fetching a large album's full asset list can take a moment — do it off the
    /// main thread with a per-row spinner rather than freezing the tap.
    private func openAlbum(_ album: AlbumInfo) {
        guard loadingAlbumID == nil else { return }
        loadingAlbumID = album.id
        Task {
            let assets = await Task.detached(priority: .userInitiated) {
                PhotoLibraryService.shared.fetchAssets(in: album.collection)
            }.value
            loadingAlbumID = nil
            pendingDeck = PendingDeck(album: album, assets: assets)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 12) {
            Picker("Filter", selection: $filter) {
                ForEach(AlbumFilter.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Menu {
                Picker("Sort", selection: $sortOption) {
                    ForEach(AlbumSortOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.12), in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

}

private struct AlbumRow: View {
    let album: AlbumInfo
    let existingSession: Session?
    let viewModel: AlbumPickerViewModel
    let isOpening: Bool

    @State private var cover: UIImage?
    private let library = PhotoLibraryService.shared

    private var countDescription: String {
        guard album.videoCount > 0 else { return "\(album.photoCount) photos" }
        guard album.photoCount > 0 else { return "\(album.videoCount) videos" }
        return "\(album.photoCount) photos · \(album.videoCount) videos"
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.15))
                if let cover {
                    Image(uiImage: cover)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(album.title).font(.body)
                    if album.isShared {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if let existingSession {
                    Text("\(countDescription) · Pass \(existingSession.currentPass) in progress")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(countDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                statusBadge
            }

            Spacer()
            if isOpening {
                ProgressView()
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear {
            if let asset = album.coverAsset {
                library.loadThumbnail(for: asset, targetSize: CGSize(width: 112, height: 112)) { loaded in
                    cover = loaded
                }
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch viewModel.status(for: album) {
        case .notStarted:
            Text("Not started")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.35))
        case .partial:
            Text("Partially sorted")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.yellow)
        case .complete:
            Label("Fully sorted", systemImage: "checkmark.circle.fill")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.green)
        }
    }
}

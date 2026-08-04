import Photos
import SwiftData
import SwiftUI

struct EndOfPassReviewView: View {
    @Bindable var viewModel: SwipeDeckViewModel
    let context: ModelContext

    @State private var showNextPass = false
    @State private var showCommit = false
    @State private var showCreateAlbumSheet = false
    @State private var albumName = ""
    @State private var isCreatingAlbum = false
    @State private var createAlbumError: String?
    @State private var entitlements = EntitlementStore.shared
    @State private var showUnlock = false

    /// Which tier the review grid and "Create Album" are currently showing.
    /// Independent of the pass boundary — purely a viewing/export filter.
    /// 0 means "all photos in the album", 1...5 means "rating >= threshold".
    @State private var displayThreshold: Int

    private let library = PhotoLibraryService.shared
    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 6)]

    init(viewModel: SwipeDeckViewModel, context: ModelContext) {
        self.viewModel = viewModel
        self.context = context
        _displayThreshold = State(initialValue: viewModel.pass + 1)
    }

    private var filteredAssets: [PHAsset] {
        guard displayThreshold > 0 else { return viewModel.allAssets }
        return viewModel.allAssets.filter { viewModel.effectiveRating($0.localIdentifier) >= displayThreshold }
    }

    private var thresholdDescription: String {
        switch displayThreshold {
        case 0: return "Showing all images"
        case 5: return "Showing ★5 images"
        default: return "Showing ★\(displayThreshold)+ or higher"
        }
    }

    /// Tap-to-toggle only makes sense at the pass's natural cutoff — that's the only
    /// boundary a swipe in this pass could have moved a photo across.
    private var canToggleFromGrid: Bool { displayThreshold == viewModel.pass + 1 }

    var body: some View {
        VStack(spacing: 0) {
            Text("\(filteredAssets.count) of \(viewModel.allAssets.count) photos")
                .font(.title2.weight(.semibold))
                .padding(.top, 24)

            thresholdSelector
                .padding(.top, 8)

            Text(canToggleFromGrid ? "Tap a photo to change its fate" : "Browsing only — pick ★\(viewModel.pass + 1)+ to edit")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 10)
                .padding(.bottom, 16)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(filteredAssets, id: \.localIdentifier) { asset in
                        SurvivorThumbnail(asset: asset, storedRating: viewModel.storedRating(asset.localIdentifier), pass: viewModel.pass, library: library)
                            .onTapGesture {
                                guard canToggleFromGrid else { return }
                                withAnimation { viewModel.toggleSurvivor(asset) }
                            }
                    }
                }
                .padding(.horizontal, 12)
            }

            VStack(spacing: 12) {
                Button {
                    albumName = "\(viewModel.session.collectionTitle) — \(thresholdDescription.replacingOccurrences(of: "Showing ", with: ""))"
                    showCreateAlbumSheet = true
                } label: {
                    Label("Create Album", systemImage: "rectangle.stack.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.black)
                }
                .disabled(filteredAssets.isEmpty)

                HStack(spacing: 12) {
                    Button("Refine further →") {
                        if nextPassNeedsUnlock {
                            showUnlock = true
                        } else {
                            viewModel.advanceToNextPass()
                            showNextPass = true
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.survivors.isEmpty)

                    Button("Finish Up") {
                        showCommit = true
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(20)
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showNextPass) {
            SwipeDeckView(session: viewModel.session, allAssets: viewModel.allAssets, context: context)
        }
        .navigationDestination(isPresented: $showCommit) {
            CommitView(session: viewModel.session, allAssets: viewModel.allAssets, context: context)
        }
        .sheet(isPresented: $showCreateAlbumSheet) {
            createAlbumSheet
        }
        .sheet(isPresented: $showUnlock) {
            UnlockView()
        }
    }

    /// The pass "Refine further" would start promotes ratings to `viewModel.pass + 2`
    /// (finishing pass N leaves survivors at N+1; the *next* pass promotes N+1 → N+2).
    private var nextPassNeedsUnlock: Bool {
        (viewModel.pass + 2) > EntitlementStore.freeStarCap && !entitlements.isUnlocked
    }

    private var createAlbumSheet: some View {
        NavigationStack {
            Form {
                Section("Album name") {
                    TextField("Album name", text: $albumName)
                }
                if let createAlbumError {
                    Section {
                        Text(createAlbumError).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCreateAlbumSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isCreatingAlbum ? "Creating…" : "Create") {
                        createAlbum()
                    }
                    .disabled(albumName.trimmingCharacters(in: .whitespaces).isEmpty || isCreatingAlbum)
                }
            }
        }
        .presentationDetents([.height(220)])
    }

    private var thresholdSelector: some View {
        VStack(spacing: 10) {
            Text(thresholdDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                Button {
                    displayThreshold = 0
                } label: {
                    Text("All")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(displayThreshold == 0 ? .black : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(displayThreshold == 0 ? Color.white : Color.white.opacity(0.15), in: Capsule())
                }

                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= displayThreshold ? "star.fill" : "star")
                            .font(.title3)
                            .foregroundStyle(star <= displayThreshold ? .yellow : .white.opacity(0.4))
                            .onTapGesture { displayThreshold = star }
                    }
                }
            }
        }
    }

    private func createAlbum() {
        isCreatingAlbum = true
        createAlbumError = nil
        let name = albumName
        let assets = filteredAssets
        Task {
            do {
                try await library.createAlbum(title: name, assets: assets)
                await MainActor.run {
                    isCreatingAlbum = false
                    showCreateAlbumSheet = false
                }
            } catch {
                await MainActor.run {
                    isCreatingAlbum = false
                    createAlbumError = "Couldn't create album: \(error.localizedDescription)"
                }
            }
        }
    }
}

private struct SurvivorThumbnail: View {
    let asset: PHAsset
    let storedRating: Int?
    let pass: Int
    let library: PhotoLibraryService

    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(Color(white: 0.15))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            Text("★\(storedRating ?? 0)")
                .font(.caption2.weight(.bold))
                .padding(4)
                .background(.black.opacity(0.5), in: Capsule())
                .padding(4)
        }
        .aspectRatio(1, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            library.loadThumbnail(for: asset, targetSize: CGSize(width: 180, height: 180)) { loaded in
                image = loaded
            }
        }
    }
}

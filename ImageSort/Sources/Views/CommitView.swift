import Photos
import SwiftData
import SwiftUI

/// Final cleanup step. The only screen besides the review grid's "Create Album"
/// CTA where the real photo library is mutated.
struct CommitView: View {
    let session: Session
    let allAssets: [PHAsset]
    let context: ModelContext

    @State private var tierInput = "3"
    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var showDeleteConfirmation = false

    private let library = PhotoLibraryService.shared

    private func rating(_ assetIdentifier: String) -> Int {
        var descriptor = FetchDescriptor<PhotoRating>(
            predicate: #Predicate { $0.assetIdentifier == assetIdentifier }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first?.rating ?? 0
    }

    private var discardedAssets: [PHAsset] {
        allAssets.filter { rating($0.localIdentifier) == 0 }
    }

    private var topTierAssets: [PHAsset] {
        allAssets.filter { rating($0.localIdentifier) >= 5 }
    }

    var body: some View {
        Form {
            Section("Create a tier album") {
                Stepper("Rating ≥ \(tierInput)", value: Binding(
                    get: { Int(tierInput) ?? 3 },
                    set: { tierInput = "\($0)" }
                ), in: 1...5)
                Button {
                    createTierAlbum()
                } label: {
                    if isWorking {
                        ProgressView()
                    } else {
                        Text("Create Album for ★\(tierInput)+")
                    }
                }
                .disabled(isWorking || assetsAtOrAbove(Int(tierInput) ?? 3).isEmpty)
            }

            Section("Favorites") {
                Button("Mark ★5 as Favorites (\(topTierAssets.count))") {
                    markFavorites()
                }
                .disabled(isWorking || topTierAssets.isEmpty)
            }

            Section("Cleanup") {
                Button("Delete Discards (\(discardedAssets.count))", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .disabled(isWorking || discardedAssets.isEmpty)
            }

            if let statusMessage {
                Section {
                    Text(statusMessage).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Finish Up")
        .confirmationDialog(
            "Delete \(discardedAssets.count) photos?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteDiscards() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They'll move to Recently Deleted in Photos.")
        }
    }

    private func assetsAtOrAbove(_ tier: Int) -> [PHAsset] {
        allAssets.filter { rating($0.localIdentifier) >= tier }
    }

    private func createTierAlbum() {
        let tier = Int(tierInput) ?? 3
        let assets = assetsAtOrAbove(tier)
        isWorking = true
        statusMessage = nil
        Task {
            do {
                _ = try await library.createAlbum(title: "\(session.collectionTitle) — ★\(tier)+", assets: assets)
                await MainActor.run {
                    isWorking = false
                    statusMessage = "Created album with \(assets.count) photos."
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    statusMessage = "Couldn't create album: \(error.localizedDescription)"
                }
            }
        }
    }

    private func markFavorites() {
        let assets = topTierAssets
        isWorking = true
        statusMessage = nil
        Task {
            do {
                try await library.setFavorite(assets, favorite: true)
                await MainActor.run {
                    isWorking = false
                    statusMessage = "Marked \(assets.count) photos as favorites."
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    statusMessage = "Couldn't set favorites: \(error.localizedDescription)"
                }
            }
        }
    }

    private func deleteDiscards() {
        let assets = discardedAssets
        isWorking = true
        statusMessage = nil
        Task {
            do {
                try await library.deleteAssets(assets)
                await MainActor.run {
                    isWorking = false
                    statusMessage = "Deleted \(assets.count) photos."
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    statusMessage = "Couldn't delete: \(error.localizedDescription)"
                }
            }
        }
    }
}

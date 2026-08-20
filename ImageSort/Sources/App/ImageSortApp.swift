import SwiftData
import SwiftUI

@main
struct ImageSortApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([PhotoRating.self, Session.self, ReviewedAsset.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Migration failed — likely schema drift from an older build. Move the
            // corrupt store aside and create a fresh container. This loses ratings
            // but beats a permanent crash loop. Log it so we can see how often this
            // happens and whether a proper migration plan is worth the complexity.
            print("❌ ModelContainer creation failed: \(error)")
            print("⚠️  Creating fresh container — existing ratings will be lost")

            // Move the old store out of the way
            if let storeURL = configuration.url {
                let backupURL = storeURL.deletingLastPathComponent()
                    .appendingPathComponent("corrupted-\(Date.now.timeIntervalSince1970).store")
                try? FileManager.default.moveItem(at: storeURL, to: backupURL)
                print("📦 Moved corrupt store to \(backupURL.lastPathComponent)")
            }

            // Try one more time with a clean slate
            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                // If this still fails, something is fundamentally broken
                fatalError("Failed to create ModelContainer even after removing old store: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}

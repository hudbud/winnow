import SwiftData
import SwiftUI

@main
struct ImageSortApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([PhotoRating.self, Session.self, ReviewedAsset.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}

import SwiftUI
import SwiftData
// import FirebaseCore // Commented out - Firebase optional for now

@main
struct GroceryNotesApp: App {
    let container: ModelContainer

    init() {
        // FirebaseApp.configure() // Commented out - Firebase optional for now

        // Create a single ModelContainer for the entire app with migration support
        let schema = Schema([
            GroceryNote.self,
            GroceryItem.self,
            RecurringItem.self,
            ItemKnowledge.self,
            MealDraft.self
        ])

        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // If there's a schema mismatch, try to delete and recreate
            print("⚠️ ModelContainer creation failed: \(error)")
            print("🔄 Attempting to reset database...")

            // Get the database URL and try to delete it
            let url = URL.applicationSupportDirectory.appending(path: "default.store")
            try? FileManager.default.removeItem(at: url)

            // Try creating container again
            do {
                container = try ModelContainer(for: schema, configurations: [modelConfiguration])
                print("✅ Database reset successful")
            } catch {
                fatalError("Failed to create ModelContainer even after reset: \(error)")
            }
        }

        // Seed data using the main container
        let mainContext = container.mainContext
        Task { @MainActor in
            SeedData.seedIfNeeded(modelContext: mainContext)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
                .onAppear {
                    configureCustomFont()
                }
        }
        .modelContainer(container) // Use the single container
    }

    private func configureCustomFont() {
        // Configure navigation bar font
        let navigationBarAppearance = UINavigationBarAppearance()
        navigationBarAppearance.configureWithDefaultBackground()
        navigationBarAppearance.titleTextAttributes = [
            .font: UIFont(name: "Outfit-SemiBold", size: 17) ?? UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        navigationBarAppearance.largeTitleTextAttributes = [
            .font: UIFont(name: "Outfit-Bold", size: 34) ?? UIFont.systemFont(ofSize: 34, weight: .bold)
        ]
        UINavigationBar.appearance().standardAppearance = navigationBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationBarAppearance
        UINavigationBar.appearance().compactAppearance = navigationBarAppearance
    }
}

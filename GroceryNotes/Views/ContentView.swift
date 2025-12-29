import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @AppStorage("skipFirebase") private var skipFirebase = true // Default to skip Firebase

    var body: some View {
        TabView(selection: $selectedTab) {
            NotesListView()
                .tabItem {
                    Label("Notes", systemImage: "cart")
                }
                .tag(0)

            MealsView()
                .tabItem {
                    Label("Recipes", systemImage: "fork.knife")
                }
                .tag(1)
        }
        .applyOutfitFont()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            GroceryNote.self,
            GroceryItem.self,
            RecurringItem.self,
            ItemKnowledge.self,
            MealDraft.self
        ])
}

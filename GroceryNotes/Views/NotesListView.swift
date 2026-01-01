import SwiftUI
import SwiftData

struct NotesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GroceryNote.createdAt, order: .reverse) private var notes: [GroceryNote]

    @State private var showingNewNoteOptions = false
    @State private var selectedNote: GroceryNote?
    @State private var showingJoinList = false
    @State private var showingProfile = false
    @State private var authService = FirebaseAuthService.shared

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Background color
                Color(red: 0.882, green: 0.882, blue: 0.882) // #E1E1E1
                    .ignoresSafeArea()

                // Profile and "+" buttons in top corners
                VStack {
                    HStack {
                        // Profile button (top left)
                        Button {
                            showingProfile = true
                        } label: {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.black)
                        }
                        .padding(.leading, 24)
                        .padding(.top, 16)

                        Spacer()

                        // "+" button (top right)
                        Menu {
                            Button {
                                let newNote = createNewNote(withRecurringItems: true)
                                selectedNote = newNote
                            } label: {
                                Label("Include Essential Items", systemImage: "list.bullet")
                            }

                            Button {
                                let newNote = createNewNote(withRecurringItems: false)
                                selectedNote = newNote
                            } label: {
                                Label("Start from Scratch", systemImage: "doc")
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.black)
                        }
                        .padding(.trailing, 24)
                        .padding(.top, 16)
                    }
                    Spacer()
                }
                .zIndex(1)

                List {
                    // WhiteNana image as first item
                    Image("WhiteNana")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 150)
                        .blendMode(.multiply)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 16, leading: 24, bottom: 0, trailing: 24))
                        .listRowSeparator(.hidden)

                    // Title as second item
                    Text("Groceries")
                        .font(.outfit(52, weight: .medium))
                        .lineSpacing(64 - 52)
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 24, bottom: 16, trailing: 24))
                        .listRowSeparator(.hidden)

                    // Note previews
                    ForEach(notes) { note in
                        Button {
                            selectedNote = note
                        } label: {
                            NoteRowView(note: note)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 24, bottom: 8, trailing: 24))
                        .listRowSeparator(.hidden)
                    }
                    .onDelete(perform: deleteNotes)
                }
                .onAppear {
                    print("📋 Notes in list: \(notes.count)")
                    for note in notes {
                        print("  - \(note.title) (\(note.id))")
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarHidden(true)
                .sheet(isPresented: $showingJoinList) {
                    JoinListSheet { listId in
                        // Successfully joined - listId is the Firebase list ID
                        // You can navigate to it or show a success message
                    }
                }
                .sheet(isPresented: $showingProfile) {
                    ProfileSheet()
                }
                .overlay {
                    if notes.isEmpty {
                        VStack {
                            Spacer()
                            ContentUnavailableView(
                                "No Notes Yet",
                                systemImage: "cart",
                                description: Text("Tap + to create your first shopping list")
                            )
                            Spacer()
                        }
                    }
                }
                // Hidden NavigationLink for programmatic navigation
                NavigationLink(
                    destination: selectedNote.map { GroceryNoteDetailView(note: $0) },
                    isActive: Binding(
                        get: { selectedNote != nil },
                        set: { if !$0 { selectedNote = nil } }
                    )
                ) {
                    EmptyView()
                }
            }
        }
    }

    private func createNewNote(withRecurringItems: Bool) -> GroceryNote {
        print("🔵 Creating new note...")
        let newNote = GroceryNote()
        print("🔵 Note created with ID: \(newNote.id)")

        if withRecurringItems {
            let descriptor = FetchDescriptor<RecurringItem>()
            if let recurringItems = try? modelContext.fetch(descriptor) {
                print("🔵 Found \(recurringItems.count) recurring items")
                for recurringItem in recurringItems {
                    let item = GroceryItem(
                        name: recurringItem.displayName,
                        normalizedName: recurringItem.normalizedName,
                        quantity: recurringItem.defaultQuantity,
                        category: recurringItem.defaultCategory,
                        isRecurring: true,
                        storageAdvice: recurringItem.storageAdvice,
                        shelfLifeDaysMin: recurringItem.shelfLifeDaysMin,
                        shelfLifeDaysMax: recurringItem.shelfLifeDaysMax,
                        shelfLifeSource: recurringItem.source
                    )
                    item.note = newNote
                    newNote.items.append(item)
                }
            }
        }

        print("🔵 Inserting note into modelContext...")
        modelContext.insert(newNote)

        print("🔵 Attempting to save...")
        do {
            try modelContext.save()
            print("✅ Note saved successfully: \(newNote.id)")

            // Verify it was saved
            let descriptor = FetchDescriptor<GroceryNote>()
            if let allNotes = try? modelContext.fetch(descriptor) {
                print("🔍 Total notes in database after save: \(allNotes.count)")
                for note in allNotes {
                    print("  - \(note.title) (\(note.id))")
                }
            }
        } catch {
            print("❌ Failed to save note: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
        }
        return newNote
    }

    private func deleteNotes(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(notes[index])
        }
        try? modelContext.save()
    }
}

struct NoteRowView: View {
    let note: GroceryNote

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            Text(note.title)
                .font(.outfit(17, weight: .semiBold))

            // Emoji stack from items (deduplicated)
            if !note.items.isEmpty {
                let uniqueEmojis = Array(Set(note.items.map { $0.emoji })).prefix(8)
                HStack(spacing: 4) {
                    ForEach(Array(uniqueEmojis), id: \.self) { emoji in
                        Text(emoji)
                            .font(.system(size: 20))
                    }
                    if uniqueEmojis.count > 8 {
                        Text("+\(uniqueEmojis.count - 8)")
                            .font(.outfit(12))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 6) {
                if note.isCompleted, let completedAt = note.completedAt {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 14))

                    Text("Completed \(completedAt, style: .date)")
                        .font(.outfit(12))
                        .foregroundStyle(.green)
                } else {
                    Text(note.createdAt, style: .date)
                        .font(.outfit(12))
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.outfit(12))
                        .foregroundStyle(.secondary)

                    let progress = note.progress
                    Text("\(progress.checked) / \(progress.total)")
                        .font(.outfit(12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            ZStack {
                // Backdrop blur effect
                VisualEffectBlur(blurStyle: .extraLight, alpha: 0.5)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                // White stroke border
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.white, lineWidth: 1)
            }
        )
    }
}

// MARK: - Profile Sheet

struct ProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var authService = FirebaseAuthService.shared
    @State private var showingSignOutConfirmation = false
    @AppStorage("skipFirebase") private var skipFirebase = false

    var body: some View {
        NavigationStack {
            List {
                // Account Info Section
                Section {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 4) {
                            if let user = authService.currentUser {
                                if user.isAnonymous {
                                    Text("Guest Account")
                                        .font(.headline)
                                    Text("Anonymous")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if let email = user.email {
                                    Text(email)
                                        .font(.headline)
                                    Text("Signed In")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Signed In")
                                        .font(.headline)
                                }
                            } else {
                                Text("Not Signed In")
                                    .font(.headline)
                            }
                        }
                        .padding(.leading, 12)
                    }
                    .padding(.vertical, 8)
                }

                // Actions Section
                if !skipFirebase && authService.currentUser != nil {
                    Section {
                        Button(role: .destructive) {
                            showingSignOutConfirmation = true
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                Text("Sign Out")
                            }
                        }
                    }
                }

                // App Info Section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Firebase")
                        Spacer()
                        Text(skipFirebase ? "Disabled" : "Enabled")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("App Info")
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Sign Out", isPresented: $showingSignOutConfirmation) {
                Button("Sign Out", role: .destructive) {
                    handleSignOut()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
    }

    private func handleSignOut() {
        do {
            try authService.signOut()
            dismiss()
        } catch {
            print("❌ Sign out failed: \(error)")
        }
    }
}

#Preview {
    NotesListView()
        .modelContainer(for: [GroceryNote.self, GroceryItem.self, RecurringItem.self])
}

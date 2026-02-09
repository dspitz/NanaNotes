import SwiftUI
import SwiftData
import FirebaseFirestore

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {

        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

// MARK: - OpenAI Response Models
private struct OpenAIClassificationResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            var content: String
        }
        var message: Message
    }
    var choices: [Choice]
}

struct GroceryNoteDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var note: GroceryNote

    @State private var newItemName = ""
    @State private var selectedItem: GroceryItem?
    @State private var showingEditSheet = false
    @State private var viewMode: ViewMode = .ordered
    @FocusState private var isInputFocused: Bool
    @StateObject private var keyboardResponder = KeyboardResponder()

    // Voice recording states
    @State private var isRecording = false
    @State private var recordingPermissionDenied = false
    @State private var currentTranscription = ""
    @State private var showingPermissionAlert = false
    @State private var speechService: SpeechRecognitionService?
    @State private var showingVoiceConfirmation = false
    @State private var parsedVoiceItems: [ParsedIngredient] = []

    // Recipe/Meal states
    @State private var showingRecipeSheet = false
    @State private var currentRecipe: MealRecipe?
    @State private var isLoadingRecipe = false
    @State private var isLoadingImage = false
    @State private var mealDrafts: [MealDraft] = []
    @State private var pendingMealIdea: String?
    @State private var showingMealIdeaPrompt = false
    @State private var showingPopularRecipesSheet = false

    // Sharing states
    @State private var showingShareSheet = false
    @State private var isCreatingFirebaseList = false
    @State private var shareURL: URL?
    @State private var isGeneratingShareLink = false
    @State private var listMembers: [String: String] = [:] // userId: role
    @State private var listOwnerId: String?
    @State private var showingMemberManagement = false
    @State private var showingNativeShareSheet = false
    @State private var shareError: String?

    // Scroll to newly added item
    @State private var scrollToItemId: UUID?
    @State private var animatingEmojiItemId: UUID?

    // Expansion state for inline editing
    @State private var expandedItemId: UUID?
    @State private var editingItemId: UUID?
    @State private var sourceFrame: CGRect = .zero
    @State private var isExpanding: Bool = false  // Track expansion animation state
    @State private var expandedHeight: CGFloat = 0  // Track measured expanded height
    @Namespace private var expansionNamespace

    enum ViewMode: String, CaseIterable {
        case ordered = "Aisles"
        case unordered = "Items"
        case meals = "Meals"
    }

    private var groupedItems: [(category: GroceryCategory, items: [GroceryItem])] {
        let sorted = CategoryOrder.sortedCategories()
        return sorted.compactMap { category in
            let items = note.items.filter { $0.category == category }
            return items.isEmpty ? nil : (category, items)
        }
    }

    private var unorderedItems: [GroceryItem] {
        note.items.sorted { $0.createdAt < $1.createdAt }
    }

    private var backgroundColor: some View {
        Color(red: 0.941, green: 0.941, blue: 0.937) // #F0F0EF
            .ignoresSafeArea()
    }

    @ViewBuilder
    private var headerView: some View {
        if !keyboardResponder.isKeyboardVisible {
            ViewModeSegmentedControl(selectedMode: $viewMode)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(Color(red: 0.941, green: 0.941, blue: 0.937)) // #F0F0EF
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var gradientScrim: some View {
        VStack {
            Spacer()
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.882, green: 0.882, blue: 0.882).opacity(0),
                    Color(red: 0.882, green: 0.882, blue: 0.882).opacity(1)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var floatingInputBar: some View {
        FloatingAddItemBar(
            newItemName: $newItemName,
            isInputFocused: _isInputFocused,
            isRecording: $isRecording,
            currentTranscription: currentTranscription,
            onAdd: {
                handleInputSubmission()
            },
            onMicrophoneTap: toggleRecording
        )
    }

    private var mealIdeaPromptBar: some View {
        VStack(spacing: 0) {
            Button {
                if let mealIdea = pendingMealIdea {
                    searchPopularRecipes(mealIdea)
                    showingMealIdeaPrompt = false
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 18))
                        .foregroundStyle(.black)
                    Text("Search Popular Recipes")
                        .font(.outfit(15, weight: .medium))
                        .foregroundStyle(.black)
                    Spacer()
                }
                .frame(height: 48)
            }

            Divider()
                .padding(.horizontal, 0)

            Button {
                if let mealIdea = pendingMealIdea {
                    Task {
                        do {
                            let categorizationService = CategorizationService(modelContext: modelContext)
                            let normalized = await categorizationService.normalizeItemName(mealIdea)
                            let (category, knowledge) = try await categorizationService.categorizeItem(mealIdea)

                            await MainActor.run {
                                let item = GroceryItem(
                                    name: mealIdea,
                                    normalizedName: normalized,
                                    category: category,
                                    storageAdvice: knowledge?.storageAdvice,
                                    shelfLifeDaysMin: knowledge?.shelfLifeDaysMin,
                                    shelfLifeDaysMax: knowledge?.shelfLifeDaysMax,
                                    shelfLifeSource: knowledge?.source
                                )
                                item.note = note
                                note.items.append(item)
                                note.updatedAt = Date()
                                try? modelContext.save()
                                newItemName = ""
                            }
                        } catch {
                            await MainActor.run {
                                let item = GroceryItem(
                                    name: mealIdea,
                                    normalizedName: mealIdea.lowercased(),
                                    category: .other
                                )
                                item.note = note
                                note.items.append(item)
                                note.updatedAt = Date()
                                try? modelContext.save()
                                newItemName = ""
                            }
                        }
                    }
                }
                showingMealIdeaPrompt = false
                pendingMealIdea = nil
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 18))
                        .foregroundStyle(.black)
                    Text("Add to List as Item")
                        .font(.outfit(15, weight: .medium))
                        .foregroundStyle(.black)
                    Spacer()
                }
                .frame(height: 48)
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if isLoadingRecipe {
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("Loading recipe...")
                        .foregroundStyle(.white)
                        .font(.outfit(17, weight: .semiBold))
                }
                .padding(32)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemGray6))
                )
            }
            .transition(.opacity)
        }
    }

    private func scrollableContent(proxy: ScrollViewProxy) -> some View {
        List {
            switch viewMode {
            case .ordered:
                        ForEach(groupedItems, id: \.category) { category, items in
                            // Category header as a list row
                            Text(category.rawValue)
                                .font(.outfit(36, weight: .medium))
                                .lineSpacing(44 - 36) // Line height 44px minus font size 36px
                                .foregroundStyle(Color.black)
                                .textCase(nil)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 8)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 16, leading: 24, bottom: 8, trailing: 24))
                                .listRowSeparator(.hidden)
                                .zIndex(0) // Title at lower z-index

                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                let position: ItemRowView.Position = {
                                    if items.count == 1 {
                                        return .only
                                    } else if index == 0 {
                                        return .first
                                    } else if index == items.count - 1 {
                                        return .last
                                    } else {
                                        return .middle
                                    }
                                }()

                                ItemRowView(
                                    item: item,
                                    position: position,
                                    isAppearing: animatingEmojiItemId == item.id,
                                    isExpanded: expandedItemId == item.id,
                                    namespace: expansionNamespace,
                                    onTap: { frame in
                                        print("🎯 Tapped item: \(item.name)")
                                        print("📏 Source frame: \(frame)")
                                        print("   - Origin: (\(frame.minX), \(frame.minY))")
                                        print("   - Size: \(frame.width) × \(frame.height)")
                                        print("   - Center: (\(frame.midX), \(frame.midY))")

                                        sourceFrame = frame
                                        isExpanding = false
                                        expandedItemId = item.id
                                        // Trigger expansion animation after view appears
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                                isExpanding = true
                                            }
                                        }
                                    }
                                )
                                .id(item.id)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: -0.5, leading: 24, bottom: -0.5, trailing: 24))
                                .listRowSeparator(.hidden)
                                .zIndex(1) // Items at higher z-index to appear above title
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        deleteItem(item)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                }
                            .contextMenu {
                                Button {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                        expandedItemId = item.id
                                    }
                                } label: {
                                    Label("Expand", systemImage: "arrow.up.left.and.arrow.down.right")
                                }

                                Button {
                                    selectedItem = item
                                    showingEditSheet = true
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }

                                Menu {
                                    ForEach(GroceryCategory.allCases, id: \.self) { cat in
                                        Button(cat.rawValue) {
                                            item.category = cat
                                            note.updatedAt = Date()
                                            try? modelContext.save()
                                        }
                                    }
                                } label: {
                                    Label("Move to Category", systemImage: "folder")
                                }
                            }
                        }
                    }

                    if note.items.count >= 3 {
                        InstacartCTAView(items: Array(note.items))
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 24, leading: 24, bottom: 16, trailing: 24))
                            .listRowSeparator(.hidden)
                    }

                case .unordered:
                    ForEach(Array(unorderedItems.enumerated()), id: \.element.id) { index, item in
                        let position: ItemRowView.Position = {
                            if unorderedItems.count == 1 {
                                return .only
                            } else if index == 0 {
                                return .first
                            } else if index == unorderedItems.count - 1 {
                                return .last
                            } else {
                                return .middle
                            }
                        }()

                        ItemRowView(
                            item: item,
                            position: position,
                            isAppearing: animatingEmojiItemId == item.id,
                            isExpanded: expandedItemId == item.id,
                            namespace: expansionNamespace,
                            onTap: { frame in
                                print("🎯 Tapped item: \(item.name)")
                                print("📏 Source frame: \(frame)")
                                print("   - Origin: (\(frame.minX), \(frame.minY))")
                                print("   - Size: \(frame.width) × \(frame.height)")
                                print("   - Center: (\(frame.midX), \(frame.midY))")

                                sourceFrame = frame
                                isExpanding = false
                                expandedItemId = item.id
                                // Trigger expansion animation after view appears
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                        isExpanding = true
                                    }
                                }
                            }
                        )
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: -0.5, leading: 24, bottom: -0.5, trailing: 24))
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleteItem(item)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                        .contextMenu {
                            Button {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    expandedItemId = item.id
                                }
                            } label: {
                                Label("Expand", systemImage: "arrow.up.left.and.arrow.down.right")
                            }

                            Button {
                                selectedItem = item
                                showingEditSheet = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }

                            Menu {
                                ForEach(GroceryCategory.allCases, id: \.self) { cat in
                                    Button(cat.rawValue) {
                                        item.category = cat
                                        note.updatedAt = Date()
                                        try? modelContext.save()
                                    }
                                }
                            } label: {
                                Label("Move to Category", systemImage: "folder")
                            }
                        }
                    }

                    if unorderedItems.count >= 3 {
                        InstacartCTAView(items: unorderedItems)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 24, leading: 24, bottom: 16, trailing: 24))
                            .listRowSeparator(.hidden)
                    }

                case .meals:
                    if mealDrafts.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "fork.knife")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("No Meal Ideas Yet")
                                .font(.outfit(17, weight: .semiBold))
                            Text("Paste a recipe URL or enter a dish name like \"Chicken Parm\" to get started")
                                .font(.outfit(15))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16)
                        ], spacing: 16) {
                            ForEach(mealDrafts) { draft in
                                if let recipe = draft.selectedRecipe {
                                    RecipeCard(
                                        recipe: recipe,
                                        onTap: {
                                            currentRecipe = recipe
                                            showingRecipeSheet = true
                                        },
                                        onDelete: {
                                            deleteMealDraft(draft)
                                        }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                    }
                }
            }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listSectionSeparator(.hidden)
        .environment(\.defaultMinListHeaderHeight, 0)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 180)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { _ in
                    // Dismiss keyboard when scrolling
                    if isInputFocused {
                        isInputFocused = false
                    }
                }
        )
        .onTapGesture {
            // Dismiss keyboard when tapping on list
            isInputFocused = false
            // Collapse is now handled by overlay tap gesture
        }
        .onChange(of: scrollToItemId) { _, newId in
            if let id = newId {
                // Set animation state immediately so emoji starts hidden
                animatingEmojiItemId = id

                // Scroll immediately
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(id, anchor: .top)
                }

                // Clear animation state after emoji animation completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    animatingEmojiItemId = nil
                    scrollToItemId = nil
                }
            }
        }
    }

    // MARK: - Body Helper Views

    private var backgroundLayer: some View {
        ZStack(alignment: .bottom) {
            backgroundColor

            VStack(spacing: 0) {
                headerView

                ScrollViewReader { proxy in
                    scrollableContent(proxy: proxy)
                }
            }

            gradientScrim

            VStack(spacing: 0) {
                Spacer()

                if showingMealIdeaPrompt {
                    mealIdeaPromptBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                floatingInputBar
            }
            .animation(.spring(response: 0.3), value: showingMealIdeaPrompt)

            loadingOverlay
        }
        .blur(radius: isExpanding ? 8 : 0)
    }

    @ViewBuilder
    private var darkScrimOverlay: some View {
        if expandedItemId != nil {
            Color.black.opacity(isExpanding ? 0.16 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(isExpanding)
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.95)) {
                        isExpanding = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        expandedItemId = nil
                        editingItemId = nil
                    }
                }
        }
    }

    @ViewBuilder
    private var expandedItemOverlay: some View {
        if let expandedId = expandedItemId,
           let expandedItem = note.items.first(where: { $0.id == expandedId }) {
            expandedItemContent(for: expandedItem, id: expandedId)
        }
    }

    private func expandedItemContent(for expandedItem: GroceryItem, id: UUID) -> some View {
        let expandedWidth: CGFloat = UIScreen.main.bounds.width - 48
        let startWidth = sourceFrame.width
        let startHeight = sourceFrame.height
        let estimatedHeight: CGFloat = expandedItem.isRecurring ? 320 : 260
        let finalHeight: CGFloat = expandedHeight > 0 ? expandedHeight : estimatedHeight
        let startCenterX = sourceFrame.midX
        let startCenterY = sourceFrame.midY
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        let targetCenterX = screenWidth / 2
        let targetCenterY = screenHeight / 2

        return ZStack {
            Color.clear
        }
        .overlay {
            FloatingExpandedItemView(
                item: expandedItem,
                isEditing: editingItemId == id,
                isExpanding: isExpanding,
                namespace: expansionNamespace,
                onEditTap: {
                    editingItemId = id
                },
                onEditComplete: { newName in
                    expandedItem.name = newName
                    expandedItem.normalizedName = newName.lowercased().trimmingCharacters(in: .whitespaces)
                    expandedItem.updatedAt = Date()
                    editingItemId = nil
                    try? modelContext.save()
                },
                onQuantityChange: { delta in
                    updateQuantity(for: expandedItem, delta: delta)
                },
                onToggleRecurring: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        expandedItem.toggleRecurring()
                    }
                    updateRecurringItem(expandedItem)
                    try? modelContext.save()
                },
                onSeasonalityChange: { seasonality in
                    updateSeasonality(for: expandedItem, seasonality: seasonality)
                },
                onClose: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.95)) {
                        isExpanding = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        expandedItemId = nil
                        editingItemId = nil
                    }
                }
            )
            .background(
                GeometryReader { expandedGeo in
                    Color.clear
                        .preference(key: ExpandedHeightPreferenceKey.self, value: expandedGeo.size.height)
                }
            )
            .onPreferenceChange(ExpandedHeightPreferenceKey.self) { newHeight in
                if expandedHeight != newHeight {
                    expandedHeight = newHeight
                }
            }
            .frame(
                width: isExpanding ? expandedWidth : startWidth,
                height: isExpanding ? finalHeight : startHeight
            )
            .position(
                x: isExpanding ? targetCenterX : startCenterX,
                y: isExpanding ? targetCenterY : startCenterY
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(true)
        .zIndex(100)
    }

    var body: some View {
        ZStack {
            backgroundLayer
            darkScrimOverlay
            expandedItemOverlay
        }
        .animation(.easeInOut(duration: 0.25), value: keyboardResponder.isKeyboardVisible)
        .navigationTitle(note.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(.blue)
                }
            }

            // Custom title
            ToolbarItem(placement: .principal) {
                Text(note.title)
                    .font(.outfit(17, weight: .semiBold))
            }

            // Member count and share button
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    // Show member count if list is shared (excluding current user)
                    if note.firebaseListId != nil, !listMembers.isEmpty {
                        Button {
                            showingMemberManagement = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 14))
                                Text("\(listMembers.count)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Capsule())
                        }
                    }

                    // Share button
                    Button {
                        handleShareTap()
                    } label: {
                        if isGeneratingShareLink {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(.blue)
                        }
                    }
                    .disabled(isGeneratingShareLink)
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let listId = note.firebaseListId {
                ShareListSheet(note: note, listId: listId)
            } else if isCreatingFirebaseList {
                ProgressView("Creating shareable list...")
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            if let item = selectedItem {
                EditItemSheet(item: item)
            } else {
                EditNoteSheet(note: note)
            }
        }
        .sheet(isPresented: $showingRecipeSheet) {
            RecipeIngredientSelectionSheet(
                recipe: $currentRecipe,
                note: note,
                isLoadingRecipe: $isLoadingRecipe,
                isLoadingImage: $isLoadingImage,
                onIngredientsAdded: { firstItemId in
                    viewMode = .ordered
                    if let itemId = firstItemId {
                        scrollToItemId = itemId
                    }
                }
            )
        }
        .onChange(of: viewMode) { _, newMode in
            if newMode == .meals {
                // Reload meal drafts when switching to meals view to show new recipes
                loadMealDrafts()
            }
        }
        .sheet(isPresented: $showingMemberManagement) {
            MemberManagementSheet(
                members: listMembers,
                ownerId: listOwnerId,
                currentUserId: FirebaseAuthService.shared.currentUser?.uid,
                onRemoveMember: removeMember
            )
        }
        .sheet(isPresented: $showingNativeShareSheet) {
            if let url = shareURL {
                let shareCode = url.pathComponents.last ?? ""
                let message = "Join my shopping list '\(note.title)' on Nana Notes! Use code: \(shareCode) or tap the link to join instantly."
                ShareSheet(items: [url, message])
            }
        }
        .alert("Share Error", isPresented: .constant(shareError != nil)) {
            Button("OK") {
                shareError = nil
            }
        } message: {
            if let error = shareError {
                Text(error)
            }
        }
        .onAppear {
            if note.firebaseListId != nil {
                fetchListMembers()
            }
        }
        .onChange(of: note.firebaseListId) { _, newListId in
            if newListId != nil {
                // Delay fetching to allow Firebase list to be fully created
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    await MainActor.run {
                        fetchListMembers()
                    }
                }
            }
        }
        .sheet(isPresented: $showingPopularRecipesSheet) {
            PopularRecipesSheet(searchQuery: pendingMealIdea ?? "") { selectedRecipe in
                // Recipe was saved from within the search sheet
                currentRecipe = selectedRecipe
                isLoadingRecipe = false

                // Reload meal drafts to show the new recipe in meals tab
                loadMealDrafts()

                // Close the search sheet and switch to meals tab
                showingPopularRecipesSheet = false
                viewMode = .meals
            }
        }
        .onChange(of: showingPopularRecipesSheet) { _, isShowing in
            if !isShowing {
                pendingMealIdea = nil
            }
        }
        .sheet(isPresented: $showingVoiceConfirmation) {
            VoiceInputConfirmationSheet(
                parsedItems: parsedVoiceItems,
                onConfirm: confirmVoiceItems
            )
        }
        .alert("Microphone Permission Required", isPresented: $showingPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please enable microphone and speech recognition in Settings to use voice input.")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            if isRecording {
                Task {
                    await cleanupRecording()
                }
            }
        }
        .onAppear {
            // Only create speech service if it doesn't exist
            if speechService == nil {
                speechService = SpeechRecognitionService()
            }
            loadMealDrafts()
        }
        .onDisappear {
            // Clean up speech service when view disappears
            cleanupSpeechService()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Clean up audio resources when app goes to background
            if newPhase == .background || newPhase == .inactive {
                if isRecording {
                    Task {
                        await stopRecording()
                    }
                }
                cleanupSpeechService()
            }
        }
    }

    // MARK: - Sharing Functions

    private func prepareForSharing() {
        // If already has Firebase list, show share sheet
        if note.firebaseListId != nil {
            showingShareSheet = true
            return
        }

        // Otherwise, create Firebase list first
        isCreatingFirebaseList = true
        showingShareSheet = true

        Task {
            do {
                guard let userId = FirebaseAuthService.shared.currentUser?.uid else {
                    print("❌ No authenticated user")
                    await MainActor.run {
                        isCreatingFirebaseList = false
                        showingShareSheet = false
                    }
                    return
                }

                print("🔵 Creating Firebase list for note: \(note.title)")
                let listId = try await FirestoreSyncService.shared.createList(
                    title: note.title,
                    userId: userId
                )

                await MainActor.run {
                    note.firebaseListId = listId
                    isCreatingFirebaseList = false
                    print("✅ Firebase list created: \(listId)")
                }
            } catch {
                print("❌ Failed to create Firebase list: \(error)")
                await MainActor.run {
                    isCreatingFirebaseList = false
                    showingShareSheet = false
                }
            }
        }
    }

    private func handleShareTap() {
        if shareURL != nil {
            // URL already exists, show share sheet
            showingNativeShareSheet = true
        } else {
            // Generate URL first, then show share sheet
            generateShareLink()
        }
    }

    private func generateShareLink() {
        isGeneratingShareLink = true
        shareError = nil

        Task {
            do {
                // Ensure we have a Firebase list
                var listId = note.firebaseListId

                if listId == nil {
                    // Create Firebase list first
                    guard let userId = FirebaseAuthService.shared.currentUser?.uid else {
                        print("❌ No authenticated user")
                        await MainActor.run {
                            isGeneratingShareLink = false
                            shareError = "Please sign in to share lists"
                        }
                        return
                    }

                    print("🔵 Creating Firebase list for sharing: \(note.title)")
                    listId = try await FirestoreSyncService.shared.createList(
                        title: note.title,
                        userId: userId
                    )

                    await MainActor.run {
                        note.firebaseListId = listId
                        note.updatedAt = Date()
                        try? modelContext.save()
                        print("✅ Firebase list created: \(listId ?? "unknown")")
                    }
                }

                guard let finalListId = listId else {
                    print("❌ No list ID available")
                    await MainActor.run {
                        isGeneratingShareLink = false
                        shareError = "Failed to create shareable list"
                    }
                    return
                }

                // Generate share code
                print("🔵 Generating share code...")
                let shareCode = try await FirestoreSyncService.shared.generateShareCode(listId: finalListId)
                print("✅ Share code generated: \(shareCode)")

                // Create share URL safely
                guard let url = URL(string: "nananotes://share/\(shareCode)") else {
                    print("❌ Failed to create URL with code: \(shareCode)")
                    await MainActor.run {
                        isGeneratingShareLink = false
                        shareError = "Failed to create share link"
                    }
                    return
                }

                await MainActor.run {
                    shareURL = url
                    isGeneratingShareLink = false
                    print("✅ Share URL ready: \(url)")
                }

                // Small delay before presenting share sheet
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds

                await MainActor.run {
                    print("📤 Presenting share sheet...")
                    showingNativeShareSheet = true
                }
            } catch {
                print("❌ Failed to generate share link: \(error)")
                await MainActor.run {
                    isGeneratingShareLink = false
                    shareError = error.localizedDescription
                }
            }
        }
    }

    private func fetchListMembers() {
        guard let listId = note.firebaseListId else { return }

        Task {
            do {
                let db = Firestore.firestore()
                let doc = try await db.collection("lists").document(listId).getDocument()

                guard let data = doc.data(),
                      let members = data["members"] as? [String: String],
                      let ownerId = data["ownerId"] as? String else {
                    return
                }

                await MainActor.run {
                    listMembers = members
                    listOwnerId = ownerId
                }
            } catch {
                print("❌ Failed to fetch members: \(error)")
            }
        }
    }

    private func removeMember(_ userId: String) {
        guard let listId = note.firebaseListId else { return }

        Task {
            do {
                try await FirestoreSyncService.shared.removeMemberFromList(listId: listId, userId: userId)
                // Refresh member list
                fetchListMembers()
            } catch {
                print("❌ Failed to remove member: \(error)")
            }
        }
    }

    @ViewBuilder
    private func memberAvatar(for userId: String) -> some View {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .red]
        let colorIndex = abs(userId.hashValue) % colors.count
        let initial = userId.prefix(1).uppercased()

        Circle()
            .fill(colors[colorIndex])
            .frame(width: 28, height: 28)
            .overlay {
                Text(initial)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }
            .overlay {
                Circle()
                    .strokeBorder(.white, lineWidth: 2)
            }
    }

    // MARK: - Item Management Functions

    private func addCommaSeparatedItems(_ input: String) {
        // Split by comma and process each item
        let items = input.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !items.isEmpty else { return }

        Task {
            do {
                let categorizationService = CategorizationService(modelContext: modelContext)

                // Process each item quickly
                for itemName in items {
                    let normalized = await categorizationService.normalizeItemName(itemName)
                    let (category, knowledge) = try await categorizationService.categorizeItem(itemName)

                // Create item immediately (FAST!)
                let createdItem = await MainActor.run { () -> GroceryItem in
                    let item = GroceryItem(
                        name: itemName,
                        normalizedName: normalized,
                        category: category,
                        storageAdvice: knowledge?.storageAdvice,
                        shelfLifeDaysMin: knowledge?.shelfLifeDaysMin,
                        shelfLifeDaysMax: knowledge?.shelfLifeDaysMax,
                        shelfLifeSource: knowledge?.source
                    )
                    item.note = note
                    note.items.append(item)
                    return item
                }

                // Optionally fetch AI info in background (don't wait)
                if knowledge == nil && AppConfiguration.isOpenAIConfigured {
                    // Capture the item ID for later update
                    let itemId = createdItem.id
                    let normalizedForAI = normalized
                    let categoryForAI = category

                    Task.detached { [modelContext] in
                        do {
                            let aiService = AIStorageService(apiKey: AppConfiguration.openAIAPIKey)
                            let aiResponse = try await aiService.getStorageInfo(for: normalizedForAI)

                            // Update the item's category and storage info
                            await MainActor.run {
                                let descriptor = FetchDescriptor<GroceryItem>(
                                    predicate: #Predicate<GroceryItem> { $0.id == itemId }
                                )
                                if let foundItem = try? modelContext.fetch(descriptor).first {
                                    if let aiCategory = GroceryCategory(rawValue: aiResponse.categorySuggestion) {
                                        foundItem.category = aiCategory
                                    }
                                    foundItem.storageAdvice = aiResponse.storageAdvice
                                    foundItem.shelfLifeDaysMin = aiResponse.shelfLifeDaysMin
                                    foundItem.shelfLifeDaysMax = aiResponse.shelfLifeDaysMax
                                    foundItem.shelfLifeSource = "OpenAI"
                                    foundItem.updatedAt = Date()
                                }

                                // Cache for future use
                                let itemKnowledge = ItemKnowledge(
                                    normalizedName: normalizedForAI,
                                    categoryDefault: GroceryCategory(rawValue: aiResponse.categorySuggestion) ?? categoryForAI,
                                    storageAdvice: aiResponse.storageAdvice,
                                    shelfLifeDaysMin: aiResponse.shelfLifeDaysMin,
                                    shelfLifeDaysMax: aiResponse.shelfLifeDaysMax,
                                    source: "OpenAI"
                                )
                                modelContext.insert(itemKnowledge)
                                try? modelContext.save()
                            }
                        } catch {
                            // Silently fail - AI is optional
                        }
                    }
                }
                }

                // Save once at the end
                await MainActor.run {
                    note.updatedAt = Date()
                    try? modelContext.save()
                    newItemName = ""
                }
            } catch {
                // If categorization fails, add items with default category
                await MainActor.run {
                    for itemName in items {
                        let item = GroceryItem(
                            name: itemName,
                            normalizedName: itemName.lowercased(),
                            category: .other
                        )
                        item.note = note
                        note.items.append(item)
                    }
                    note.updatedAt = Date()
                    try? modelContext.save()
                    newItemName = ""
                }
            }
        }
    }

    private func addItem() {
        guard !newItemName.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        Task {
            do {
                let categorizationService = CategorizationService(modelContext: modelContext)
                let normalized = await categorizationService.normalizeItemName(newItemName)
                let (category, knowledge) = try await categorizationService.categorizeItem(newItemName)

                // Create item immediately with local categorization (FAST!)
                let createdItem = await MainActor.run { () -> GroceryItem in
                let item = GroceryItem(
                    name: newItemName,
                    normalizedName: normalized,
                    category: category,
                    storageAdvice: knowledge?.storageAdvice,
                    shelfLifeDaysMin: knowledge?.shelfLifeDaysMin,
                    shelfLifeDaysMax: knowledge?.shelfLifeDaysMax,
                    shelfLifeSource: knowledge?.source
                )
                item.note = note
                note.items.append(item)
                note.updatedAt = Date()

                try? modelContext.save()
                newItemName = ""

                // Switch to ordered view and scroll to new item
                viewMode = .ordered
                scrollToItemId = item.id

                return item
            }

            // Optionally fetch AI info in background (don't wait for it)
            // This won't slow down the UI
            if knowledge == nil && AppConfiguration.isOpenAIConfigured {
                // Capture the item ID to update it later
                let itemId = createdItem.id
                let normalizedForAI = normalized
                let categoryForAI = category

                Task.detached { [modelContext] in
                    do {
                        let aiService = AIStorageService(apiKey: AppConfiguration.openAIAPIKey)
                        let aiResponse = try await aiService.getStorageInfo(for: normalizedForAI)

                        // Update the item's category and storage info
                        await MainActor.run {
                            // Find the item and update it
                            let descriptor = FetchDescriptor<GroceryItem>(
                                predicate: #Predicate<GroceryItem> { $0.id == itemId }
                            )
                            if let foundItem = try? modelContext.fetch(descriptor).first {
                                if let aiCategory = GroceryCategory(rawValue: aiResponse.categorySuggestion) {
                                    foundItem.category = aiCategory
                                }
                                foundItem.storageAdvice = aiResponse.storageAdvice
                                foundItem.shelfLifeDaysMin = aiResponse.shelfLifeDaysMin
                                foundItem.shelfLifeDaysMax = aiResponse.shelfLifeDaysMax
                                foundItem.shelfLifeSource = "OpenAI"
                                foundItem.updatedAt = Date()
                            }

                            // Cache for future use
                            let itemKnowledge = ItemKnowledge(
                                normalizedName: normalizedForAI,
                                categoryDefault: GroceryCategory(rawValue: aiResponse.categorySuggestion) ?? categoryForAI,
                                storageAdvice: aiResponse.storageAdvice,
                                shelfLifeDaysMin: aiResponse.shelfLifeDaysMin,
                                shelfLifeDaysMax: aiResponse.shelfLifeDaysMax,
                                source: "OpenAI"
                            )
                            modelContext.insert(itemKnowledge)
                            try? modelContext.save()
                        }
                    } catch {
                        // Silently fail - AI is optional
                    }
                }
            }
            } catch {
                // If categorization fails, create item with default category
                await MainActor.run {
                    let item = GroceryItem(
                        name: newItemName,
                        normalizedName: newItemName.lowercased(),
                        category: .other
                    )
                    item.note = note
                    note.items.append(item)
                    note.updatedAt = Date()
                    try? modelContext.save()
                    newItemName = ""

                    // Switch to ordered view and scroll to new item
                    viewMode = .ordered
                    scrollToItemId = item.id
                }
            }
        }
    }

    // MARK: - Voice Recording Functions

    private func toggleRecording() {
        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()

        if isRecording {
            Task {
                await stopRecording()
            }
        } else {
            Task {
                await startRecording()
            }
        }
    }

    private func startRecording() async {
        guard let service = speechService else { return }

        // Request authorization
        let authorized = await service.requestAuthorization()
        guard authorized else {
            await MainActor.run {
                showingPermissionAlert = true
                recordingPermissionDenied = true
            }
            return
        }

        // Check if recognition is available
        guard await service.isAvailable() else {
            print("Speech recognition not available")
            return
        }

        do {
            await MainActor.run {
                isRecording = true
                currentTranscription = ""
                newItemName = ""
            }

            // Start recording and get transcription stream
            let stream = try await service.startRecording()

            // Listen to transcription updates
            for await transcription in stream {
                await MainActor.run {
                    currentTranscription = transcription
                    // Don't update newItemName during recording to prevent auto-submit
                    // Only update it after stopRecording() is called
                }
            }
        } catch {
            print("Recording failed: \(error.localizedDescription)")
            await MainActor.run {
                isRecording = false
            }
        }
    }

    private func stopRecording() async {
        guard let service = speechService else { return }

        let finalTranscription = await service.stopRecording()

        await MainActor.run {
            isRecording = false
            currentTranscription = finalTranscription
            // Don't update newItemName - let the confirmation sheet handle adding items

            // Parse items and show confirmation instead of auto-adding
            if !currentTranscription.isEmpty {
                parseAndShowConfirmation()
            }
        }
    }

    private func cleanupRecording() async {
        guard let service = speechService else { return }
        await service.cancelRecording()

        await MainActor.run {
            isRecording = false
            currentTranscription = ""
            newItemName = ""
        }
    }

    private func cleanupSpeechService() {
        // Cancel any active recording first
        if isRecording {
            Task {
                await cleanupRecording()
            }
        }
        // Release the speech service to free memory
        speechService = nil
    }

    private func parseAndShowConfirmation() {
        guard !currentTranscription.isEmpty else { return }

        Task {
            let parserService = VoiceInputParserService(apiKey: AppConfiguration.isOpenAIConfigured ? AppConfiguration.openAIAPIKey : nil)

            do {
                // Use existing VoiceInputParserService to parse transcription
                let parsed = try await parserService.parseTranscription(currentTranscription)

                await MainActor.run {
                    parsedVoiceItems = parsed
                    showingVoiceConfirmation = true
                }
            } catch {
                print("Voice input parsing failed: \(error.localizedDescription)")
                // On parsing failure, keep the text in the field for manual submission
            }
        }
    }

    private func confirmVoiceItems() {
        // Add the pre-parsed items from voice input
        Task {
            let categorizationService = CategorizationService(modelContext: modelContext)

            // Process each pre-parsed item
            for parsedItem in parsedVoiceItems {
                let normalized = await categorizationService.normalizeItemName(parsedItem.name)
                let (category, knowledge) = try await categorizationService.categorizeItem(parsedItem.name)

                // Capture current user info for author tracking
                let currentUserId = FirebaseAuthService.shared.currentUser?.uid
                let currentUserName = FirebaseAuthService.shared.currentUser?.displayName
                                   ?? FirebaseAuthService.shared.currentUser?.email
                                   ?? "Unknown"

                // Create the grocery item
                await MainActor.run {
                    let item = GroceryItem(
                        name: parsedItem.name,
                        normalizedName: normalized,
                        quantity: parsedItem.quantity,
                        category: category,
                        storageAdvice: knowledge?.storageAdvice,
                        shelfLifeDaysMin: knowledge?.shelfLifeDaysMin,
                        shelfLifeDaysMax: knowledge?.shelfLifeDaysMax,
                        shelfLifeSource: knowledge?.source,
                        createdByUserId: currentUserId,
                        createdByName: currentUserName
                    )
                    item.note = note
                    note.items.append(item)
                }
            }

            await MainActor.run {
                note.updatedAt = Date()
                try? modelContext.save()

                // Clear confirmation state
                parsedVoiceItems = []
                showingVoiceConfirmation = false
                currentTranscription = ""
            }
        }
    }

    private func formatTranscriptionForDisplay(_ text: String) -> String {
        // Split by common delimiters
        let delimiters = [",", ";", " and ", " & "]
        var parts = [text]

        for delimiter in delimiters {
            var newParts: [String] = []
            for part in parts {
                newParts.append(contentsOf: part.components(separatedBy: delimiter))
            }
            parts = newParts
        }

        // Clean up and filter
        let cleanedParts = parts
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // If only one item or simple input, return as-is
        if cleanedParts.count == 1 {
            return text
        }

        // Format as bulleted list
        return cleanedParts.map { "• \($0)" }.joined(separator: "\n")
    }

    // MARK: - Batch Processing

    private func addItemsBatch() {
        guard !newItemName.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        Task {
            let parserService = VoiceInputParserService(apiKey: AppConfiguration.isOpenAIConfigured ? AppConfiguration.openAIAPIKey : nil)
            let categorizationService = CategorizationService(modelContext: modelContext)

            do {
                // Parse the transcription into individual items
                let parsedItems = try await parserService.parseTranscription(currentTranscription.isEmpty ? newItemName : currentTranscription)

                // Process each item - FAST! Don't wait for AI
                for parsedItem in parsedItems {
                    let normalized = await categorizationService.normalizeItemName(parsedItem.name)
                    let (category, knowledge) = try await categorizationService.categorizeItem(parsedItem.name)

                    // Capture current user info for author tracking
                    let currentUserId = FirebaseAuthService.shared.currentUser?.uid
                    let currentUserName = FirebaseAuthService.shared.currentUser?.displayName
                                       ?? FirebaseAuthService.shared.currentUser?.email
                                       ?? "Unknown"

                    // Create the grocery item immediately (FAST!)
                    let createdItem = await MainActor.run { () -> GroceryItem in
                        let item = GroceryItem(
                            name: parsedItem.name,
                            normalizedName: normalized,
                            quantity: parsedItem.quantity,
                            category: category,
                            storageAdvice: knowledge?.storageAdvice,
                            shelfLifeDaysMin: knowledge?.shelfLifeDaysMin,
                            shelfLifeDaysMax: knowledge?.shelfLifeDaysMax,
                            shelfLifeSource: knowledge?.source,
                            createdByUserId: currentUserId,
                            createdByName: currentUserName
                        )
                        item.note = note
                        note.items.append(item)
                        return item
                    }

                    // Optionally fetch AI storage info in background (don't wait)
                    if knowledge == nil && AppConfiguration.isOpenAIConfigured {
                        // Capture the item ID for later update
                        let itemId = createdItem.id
                        let normalizedForAI = normalized
                        let categoryForAI = category

                        Task.detached { [modelContext] in
                            do {
                                let aiService = AIStorageService(apiKey: AppConfiguration.openAIAPIKey)
                                let aiResponse = try await aiService.getStorageInfo(for: normalizedForAI)

                                // Update the item's category and storage info
                                await MainActor.run {
                                    let descriptor = FetchDescriptor<GroceryItem>(
                                        predicate: #Predicate<GroceryItem> { $0.id == itemId }
                                    )
                                    if let foundItem = try? modelContext.fetch(descriptor).first {
                                        if let aiCategory = GroceryCategory(rawValue: aiResponse.categorySuggestion) {
                                            foundItem.category = aiCategory
                                        }
                                        foundItem.storageAdvice = aiResponse.storageAdvice
                                        foundItem.shelfLifeDaysMin = aiResponse.shelfLifeDaysMin
                                        foundItem.shelfLifeDaysMax = aiResponse.shelfLifeDaysMax
                                        foundItem.shelfLifeSource = "OpenAI"
                                        foundItem.updatedAt = Date()
                                    }

                                    // Cache for future use
                                    let itemKnowledge = ItemKnowledge(
                                        normalizedName: normalizedForAI,
                                        categoryDefault: GroceryCategory(rawValue: aiResponse.categorySuggestion) ?? categoryForAI,
                                        storageAdvice: aiResponse.storageAdvice,
                                        shelfLifeDaysMin: aiResponse.shelfLifeDaysMin,
                                        shelfLifeDaysMax: aiResponse.shelfLifeDaysMax,
                                        source: "OpenAI"
                                    )
                                    modelContext.insert(itemKnowledge)
                                    try? modelContext.save()
                                }
                            } catch {
                                // Silently fail - AI is optional
                            }
                        }
                    }
                }

                // Save once at the end
                await MainActor.run {
                    note.updatedAt = Date()
                    try? modelContext.save()
                    newItemName = ""
                    currentTranscription = ""
                }
            } catch {
                print("Batch processing failed: \(error.localizedDescription)")
                // Fall back to single item add
                await MainActor.run {
                    addItem()
                }
            }
        }
    }

    private func deleteItem(_ item: GroceryItem) {
        note.items.removeAll { $0.id == item.id }
        modelContext.delete(item)
        note.updatedAt = Date()
        try? modelContext.save()
    }

    private func updateRecurringItem(_ item: GroceryItem) {
        let itemNormalizedName = item.normalizedName

        if item.isRecurring {
            let descriptor = FetchDescriptor<RecurringItem>(
                predicate: #Predicate<RecurringItem> { recurring in
                    recurring.normalizedName == itemNormalizedName
                }
            )

            if let existing = try? modelContext.fetch(descriptor).first {
                existing.displayName = item.name
                existing.defaultCategory = item.category
                existing.defaultQuantity = item.quantity
                existing.updatedAt = Date()
            } else {
                let recurringItem = RecurringItem(
                    normalizedName: item.normalizedName,
                    displayName: item.name,
                    defaultCategory: item.category,
                    defaultQuantity: item.quantity,
                    storageAdvice: item.storageAdvice,
                    shelfLifeDaysMin: item.shelfLifeDaysMin,
                    shelfLifeDaysMax: item.shelfLifeDaysMax,
                    source: item.shelfLifeSource ?? "User"
                )
                modelContext.insert(recurringItem)
            }
        } else {
            let descriptor = FetchDescriptor<RecurringItem>(
                predicate: #Predicate<RecurringItem> { recurring in
                    recurring.normalizedName == itemNormalizedName
                }
            )
            if let existing = try? modelContext.fetch(descriptor).first {
                modelContext.delete(existing)
            }
        }
    }

    private func updateQuantity(for item: GroceryItem, delta: Int) {
        // Parse current quantity
        guard let currentQty = item.quantity else {
            // No quantity, set to "1"
            item.quantity = "1"
            item.updatedAt = Date()
            try? modelContext.save()
            return
        }

        // Try to extract numeric value
        let components = currentQty.components(separatedBy: CharacterSet.decimalDigits.inverted)
        let numbers = components.compactMap { Int($0) }

        if let currentValue = numbers.first {
            let newValue = max(1, currentValue + delta)
            // Replace the number but keep the unit
            let newQty = currentQty.replacingOccurrences(
                of: String(currentValue),
                with: String(newValue),
                options: [],
                range: currentQty.range(of: String(currentValue))
            )
            item.quantity = newQty
        } else {
            // Can't parse, just set to "1"
            item.quantity = "1"
        }

        item.updatedAt = Date()
        try? modelContext.save()
    }

    private func updateSeasonality(for item: GroceryItem, seasonality: RecurringSeasonality) {
        let itemNormalizedName = item.normalizedName
        let descriptor = FetchDescriptor<RecurringItem>(
            predicate: #Predicate { $0.normalizedName == itemNormalizedName }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            existing.seasonality = seasonality
            existing.updatedAt = Date()
            try? modelContext.save()
        }
    }

    // MARK: - Input Handling

    private func handleInputSubmission() {
        let input = newItemName.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }

        // Check if it's a URL
        if let url = URL(string: input), url.scheme != nil, (url.host != nil || url.absoluteString.contains("://")) {
            handleRecipeURL(input)
            return
        }

        // Check if it's comma-separated items - treat as batch
        if input.contains(",") {
            addCommaSeparatedItems(input)
            return
        }

        // Check if it looks like a meal idea (now async)
        Task {
            if await isMealIdea(input) {
                // Ask user what they want to do
                await MainActor.run {
                    pendingMealIdea = input
                    showingMealIdeaPrompt = true
                }
            } else {
                // Otherwise, handle as regular item or batch
                await MainActor.run {
                    if currentTranscription.isEmpty {
                        addItem()
                    } else {
                        addItemsBatch()
                    }
                }
            }
        }
    }

    private func isMealIdea(_ text: String) async -> Bool {
        let lowercased = text.lowercased()

        // FAST PATH: Obvious cases (no AI needed)

        // If it has bullet points, it's likely a voice transcription batch
        if text.contains("•") {
            return false
        }

        // If it contains "recipe", it's definitely a meal idea
        if lowercased.contains("recipe") {
            return true
        }

        let words = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        // If first word is a number (quantity), it's definitely a grocery item
        if words.count >= 2, let _ = Int(words[0]) {
            return false  // "2 apples", "3 bananas"
        }

        // Check for meal/cooking indicators
        let mealKeywords = [
            "bowl", "salad", "soup", "stew", "curry", "pasta", "rice", "stir fry",
            "grilled", "fried", "baked", "roasted", "sauteed", "steamed",
            "chicken parm", "pad thai", "fried rice", "tacos", "burrito", "sandwich",
            "burger", "pizza", "casserole", "lasagna", "enchiladas",
            // Desserts & baked goods
            "tart", "pie", "cake", "brownie", "cookie", "muffin", "scone",
            "pudding", "parfait", "cobbler", "crumble", "crisp", "galette",
            // Additional dish types
            "risotto", "goulash", "quiche", "torte", "cheesecake", "pancake",
            "waffle", "frittata", "omelette", "scramble"
        ]

        for keyword in mealKeywords {
            if lowercased.contains(keyword) {
                return true
            }
        }

        // Check if it's a known grocery item (instant check)
        let normalized = lowercased.trimmingCharacters(in: .whitespaces)
        let commonGroceryItems = [
            "dragon fruit", "star fruit", "passion fruit", "bell pepper", "sweet potato",
            "green beans", "ground beef", "chicken breast", "ice cream", "orange juice",
            "apple juice", "grape juice", "peanut butter", "almond butter", "cottage cheese",
            "cream cheese", "sour cream", "brown rice", "white rice", "olive oil",
            "coconut oil", "sea salt", "hot sauce", "bbq sauce", "potato chips"
        ]

        if commonGroceryItems.contains(normalized) {
            return false
        }

        // SMART PATH: AI classification for ambiguous 2-3 word inputs
        if words.count <= 3 {
            return await classifyWithAI(text)
        }

        // DEFAULT: 4+ words = likely recipe
        return true
    }

    private func classifyWithAI(_ text: String) async -> Bool {
        // Fallback if OpenAI not configured
        guard AppConfiguration.isOpenAIConfigured else {
            // Conservative: require 3+ words for recipe
            let words = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            return words.count >= 3
        }

        do {
            let systemPrompt = """
            You are a classification assistant. Determine if the input is a RECIPE/DISH or a GROCERY ITEM.

            RECIPE: Something to cook/prepare (apple tart, chicken curry, beef stew, strawberry galette)
            ITEM: An ingredient to buy (chicken breast, ground beef, fresh apples, strawberries)

            Respond with only: RECIPE or ITEM
            """

            let requestBody: [String: Any] = [
                "model": "gpt-4o-mini",
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": text]
                ],
                "temperature": 0,
                "max_tokens": 5
            ]

            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(AppConfiguration.openAIAPIKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("AI classification failed: invalid response")
                return false
            }

            let openAIResponse = try JSONDecoder().decode(OpenAIClassificationResponse.self, from: data)
            guard let content = openAIResponse.choices.first?.message.content else {
                return false
            }

            return content.uppercased().contains("RECIPE")

        } catch {
            print("AI classification failed: \(error)")
            // Fallback on error: conservative default
            return false
        }
    }

    private func handleRecipeURL(_ urlString: String) {
        guard AppConfiguration.isOpenAIConfigured else {
            print("OpenAI not configured")
            return
        }

        isLoadingRecipe = true
        newItemName = ""

        Task {
            do {
                let recipeService = RecipeParsingService()
                let aiResponse = try await recipeService.extractRecipe(from: urlString)
                let recipe = aiResponse.toMealRecipe(sourceURL: urlString)

                await MainActor.run {
                    // Create meal draft
                    let draft = MealDraft(title: recipe.title, selectedRecipe: recipe)
                    modelContext.insert(draft)
                    try? modelContext.save()

                    // Add to local array
                    mealDrafts.append(draft)

                    // Show the recipe sheet
                    currentRecipe = recipe
                    showingRecipeSheet = true
                    isLoadingRecipe = false

                    // Switch to meals tab
                    viewMode = .meals
                }
            } catch {
                await MainActor.run {
                    isLoadingRecipe = false
                    print("Failed to fetch recipe: \(error.localizedDescription)")
                }
            }
        }
    }

    private func searchPopularRecipes(_ mealName: String) {
        guard AppConfiguration.isOpenAIConfigured else {
            print("OpenAI not configured")
            return
        }

        pendingMealIdea = mealName
        newItemName = ""
        showingPopularRecipesSheet = true
    }

    private func handleMealIdea(_ mealName: String) {
        guard AppConfiguration.isOpenAIConfigured else {
            print("OpenAI not configured")
            return
        }

        // Show sheet immediately with loading states
        isLoadingRecipe = true
        isLoadingImage = false  // Skip image generation
        currentRecipe = nil
        newItemName = ""
        showingRecipeSheet = true
        viewMode = .meals

        Task {
            do {
                // Generate recipe (using optimized Phase 1 settings)
                let recipeService = AIRecipeService(apiKey: AppConfiguration.openAIAPIKey)
                let aiResponse = try await recipeService.generateRecipe(for: mealName)
                let recipe = aiResponse.toMealRecipe()

                // Update UI with recipe content
                await MainActor.run {
                    currentRecipe = recipe
                    isLoadingRecipe = false
                }

                // Image generation disabled for speed
                // do {
                //     let imageService = DALLEImageService(apiKey: AppConfiguration.openAIAPIKey)
                //     let imageURL = try await imageService.generateRecipeImage(for: recipe.title)
                //     recipe.imageURL = imageURL
                //
                //     await MainActor.run {
                //         currentRecipe = recipe
                //         isLoadingImage = false
                //     }
                // } catch {
                //     await MainActor.run {
                //         isLoadingImage = false
                //     }
                //     print("Failed to generate image: \(error.localizedDescription)")
                // }

                // Save the meal draft
                await MainActor.run {
                    let draft = MealDraft(
                        title: mealName,
                        selectedRecipe: recipe,
                        alternatives: aiResponse.toAlternatives()
                    )
                    modelContext.insert(draft)
                    try? modelContext.save()
                    mealDrafts.append(draft)
                }
            } catch {
                await MainActor.run {
                    isLoadingRecipe = false
                    isLoadingImage = false
                    showingRecipeSheet = false
                    print("❌ RECIPE ERROR: \(error)")
                    print("❌ ERROR DESCRIPTION: \(error.localizedDescription)")
                    if let decodingError = error as? DecodingError {
                        print("❌ DECODING ERROR: \(decodingError)")
                    }
                }
            }
        }
    }

    // MARK: - Meal Management

    private func loadMealDrafts() {
        let descriptor = FetchDescriptor<MealDraft>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        mealDrafts = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func deleteMealDraft(_ draft: MealDraft) {
        modelContext.delete(draft)
        try? modelContext.save()
        mealDrafts.removeAll { $0.id == draft.id }
    }
}

// Preference key for measuring expanded view height
struct ExpandedHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// Animatable font size modifier
struct AnimatableFontModifier: AnimatableModifier {
    var size: Double

    var animatableData: Double {
        get { size }
        set { size = newValue }
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size))
    }
}

// Animatable Outfit font modifier with weight support
struct AnimatableOutfitFontModifier: AnimatableModifier {
    var size: Double
    var weight: Double  // Numeric weight from 100-900

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(size, weight) }
        set {
            size = newValue.first
            weight = newValue.second
        }
    }

    func body(content: Content) -> some View {
        let uiFont = UIFont(name: fontNameForWeight(weight), size: size) ?? UIFont.systemFont(ofSize: size)
        return content.font(Font(uiFont))
    }

    private func fontNameForWeight(_ numericWeight: Double) -> String {
        // Map numeric weight to Outfit font names
        // 400 = Regular, 500 = Medium, 600 = SemiBold, 700 = Bold
        if numericWeight < 450 {
            return "Outfit-Regular"
        } else if numericWeight < 550 {
            return "Outfit-Medium"
        } else if numericWeight < 650 {
            return "Outfit-SemiBold"
        } else {
            return "Outfit-Bold"
        }
    }
}

struct ItemRowView: View {
    enum Position {
        case only       // Single item in section
        case first      // First of multiple items
        case middle     // Middle item
        case last       // Last item
    }

    @Bindable var item: GroceryItem
    let position: Position
    var isAppearing: Bool = false
    var isExpanded: Bool = false
    let namespace: Namespace.ID
    let onTap: (CGRect) -> Void  // Now passes frame

    @State private var hasAppeared: Bool = false
    @State private var itemFrame: CGRect = .zero

    private var cornerRadius: RectangleCornerRadii {
        switch position {
        case .only:
            return RectangleCornerRadii(topLeading: 12, bottomLeading: 12, bottomTrailing: 12, topTrailing: 12)
        case .first:
            return RectangleCornerRadii(topLeading: 12, bottomLeading: 0, bottomTrailing: 0, topTrailing: 12)
        case .middle:
            return RectangleCornerRadii(topLeading: 0, bottomLeading: 0, bottomTrailing: 0, topTrailing: 0)
        case .last:
            return RectangleCornerRadii(topLeading: 0, bottomLeading: 12, bottomTrailing: 12, topTrailing: 0)
        }
    }

    var body: some View {
        compactRow
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            itemFrame = geometry.frame(in: .global)
                            print("📍 ItemRowView onAppear - frame: \(itemFrame)")
                        }
                        .onChange(of: geometry.frame(in: .global)) { _, newFrame in
                            itemFrame = newFrame
                            print("📍 ItemRowView onChange - frame: \(itemFrame)")
                        }
                }
            )
            .background(
                ZStack {
                    VisualEffectBlur(blurStyle: .extraLight, alpha: 0.5)
                        .clipShape(UnevenRoundedRectangle(cornerRadii: cornerRadius))
                        .shadow(color: Color.black.opacity(0.08), radius: 28, x: 0, y: 10)

                    UnevenRoundedRectangle(cornerRadii: cornerRadius)
                        .strokeBorder(.white, lineWidth: 1)
                }
            )
            .opacity(isExpanded ? 0 : 1)
    }

    private var compactRow: some View {
        HStack(spacing: 12) {
            // Expandable tap area (everything except checkbox)
            Button {
                onTap(itemFrame)
            } label: {
                HStack(spacing: 8) {
                    IngredientImageView(
                        imageName: item.displayImageName,
                        imageURL: item.customImageURL,
                        emoji: item.emoji,
                        size: 34
                    )
                    .scaleEffect((item.isChecked || !hasAppeared) ? 0.001 : 1.0)
                    .opacity((item.isChecked || !hasAppeared) ? 0 : 1)
                    .rotationEffect(.degrees((item.isChecked || !hasAppeared) ? -90 : 0))
                    .offset(x: (item.isChecked || !hasAppeared) ? -32 : 0)
                    .frame(width: (item.isChecked || !hasAppeared) ? 0 : nil)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: hasAppeared)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: item.isChecked)
                        .onAppear {
                            if isAppearing {
                                // This is a newly added item - delay animation until after scroll completes
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    // Haptic feedback when emoji animates on
                                    let impact = UIImpactFeedbackGenerator(style: .light)
                                    impact.impactOccurred()

                                    hasAppeared = true
                                }
                            } else {
                                // Existing item - show immediately (no animation)
                                hasAppeared = true
                            }
                        }

                    Text(item.name)
                        .font(.outfit(16))
                        .strikethrough(item.isChecked)
                        .scaleEffect((isAppearing && !hasAppeared) ? 0.95 : 1.0)
                        .opacity((isAppearing && !hasAppeared) ? 0.7 : 1.0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: hasAppeared)

                    if let quantity = item.quantity {
                        Text("(\(quantity))")
                            .foregroundStyle(.secondary)
                            .font(.outfit(15))
                    }

                    Spacer(minLength: 0)
                }
                .padding(.leading, item.isChecked ? 4 : 0)
                .opacity(item.isChecked ? 0.4 : 1.0)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: item.isChecked)
                .contentShape(Rectangle())  // Makes entire area tappable
            }
            .buttonStyle(.plain)

                ZStack {
                    // Background circle
                    Circle()
                        .fill(item.isChecked ? Color.black : Color(red: 0.851, green: 0.851, blue: 0.851)) // Black when checked, #D9D9D9 when unchecked
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .strokeBorder(.white, lineWidth: 1)
                        )

                    // Checkmark icon
                    if item.isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .overlay(alignment: .center) {
                    Button {
                        // Minimal haptic feedback
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()

                        item.toggleCheck()
                        item.note?.checkIfShouldUncomplete()
                    } label: {
                        Color.clear
                            .frame(width: 68, height: 58)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .foregroundStyle(.primary)
    }

}

struct FloatingExpandedItemView: View {
    @Bindable var item: GroceryItem
    var isEditing: Bool
    var isExpanding: Bool  // Track whether we're in expanded state
    let namespace: Namespace.ID
    let onEditTap: () -> Void
    let onEditComplete: (String) -> Void
    let onQuantityChange: (Int) -> Void
    let onToggleRecurring: () -> Void
    let onSeasonalityChange: (RecurringSeasonality) -> Void
    let onClose: () -> Void

    @State private var editedName: String = ""
    @FocusState private var isEditingFocused: Bool
    @State private var showTitleBackground = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(spacing: 0) {
            // Header: Compact row (emoji, name, checkbox)
            compactHeader
                .padding(.vertical, 12)
                .padding(.horizontal, 16)

            // Quantity row - centered, above divider
            quantityRow
                .padding(.bottom, 12)
                .opacity(isExpanding ? 1 : 0)
                .animation(isExpanding ? .spring(response: 0.4, dampingFraction: 0.7) : .easeOut(duration: 0.1), value: isExpanding)
                .frame(height: isExpanding ? nil : 0)

            // Always include controls in hierarchy so they move with parent
            Divider()
                .padding(.horizontal, 16)
                .opacity(isExpanding ? 1 : 0)
                .animation(isExpanding ? .spring(response: 0.4, dampingFraction: 0.7) : .easeOut(duration: 0.1), value: isExpanding)
                .frame(height: isExpanding ? nil : 0)

            // Expanded controls
            VStack(alignment: .leading, spacing: 16) {
                recurringRow

                if item.isRecurring {
                    seasonalityRow
                }
            }
            .padding(16)
            .opacity(isExpanding ? 1 : 0)
            .animation(isExpanding ? .spring(response: 0.4, dampingFraction: 0.7) : .easeOut(duration: 0.1), value: isExpanding)
            .frame(height: isExpanding ? nil : 0)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: item.isRecurring)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)

                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.white.opacity(0.5), lineWidth: 1)
            }
        )
        .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 10)
        .onChange(of: isExpanding) { oldValue, newValue in
            if newValue {
                // When expanding, wait for animation to settle (0.5s) then fade in background
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showTitleBackground = true
                }
            } else {
                // When collapsing, immediately hide background
                showTitleBackground = false
            }
        }
    }

    private var compactHeader: some View {
        HStack(spacing: 12) {
            // Add leading spacer when expanded to center content
            if isExpanding {
                Spacer()
            }

            // Keep both layouts in hierarchy and cross-fade for smooth animation
            ZStack {
                // Vertical stack when expanded - always in hierarchy
                VStack(spacing: 8) {
                    IngredientImageView(
                        imageName: item.displayImageName,
                        imageURL: item.customImageURL,
                        emoji: item.emoji,
                        size: isExpanding ? 68 : 34
                    )

                    if isEditing {
                        TextField("Item name", text: $editedName)
                            .font(.outfit(24, weight: .semiBold))
                            .multilineTextAlignment(.center)
                            .textFieldStyle(.plain)
                            .focused($isEditingFocused)
                            .onAppear {
                                editedName = item.name
                                isEditingFocused = true
                            }
                            .onSubmit {
                                onEditComplete(editedName)
                            }
                    } else {
                        Button {
                            onEditTap()
                        } label: {
                            Text(item.name)
                                .modifier(AnimatableOutfitFontModifier(size: isExpanding ? 24 : 16, weight: isExpanding ? 600 : 400))
                                .strikethrough(item.isChecked)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.black.opacity(showTitleBackground ? 0.05 : 0))
                                )
                                .animation(.easeInOut(duration: 0.5), value: showTitleBackground)
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, isExpanding ? 12 : 0)
                    }

                    // Author attribution - only show when expanded and someone else added it
                    if isExpanding, let authorName = item.createdByName, let authorId = item.createdByUserId, !isCurrentUser(authorId) {
                        HStack(spacing: 4) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 12))
                            Text("Added by \(authorName)")
                                .font(.outfit(12))
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, isExpanding ? 24 : 0)
                .opacity(isExpanding ? 1 : 0)
                .frame(height: isExpanding ? nil : 0)
                .clipped()

                // Horizontal stack when collapsed - always in hierarchy
                HStack(spacing: 8) {
                    IngredientImageView(
                        imageName: item.displayImageName,
                        imageURL: item.customImageURL,
                        emoji: item.emoji,
                        size: 34
                    )

                    Text(item.name)
                        .font(.outfit(16))
                        .strikethrough(item.isChecked)

                    if let quantity = item.quantity {
                        Text("(\(quantity))")
                            .foregroundStyle(.secondary)
                            .font(.outfit(15))
                    }
                }
                .opacity(isExpanding ? 0 : 1)
            }
            .opacity(item.isChecked ? 0.4 : 1.0)

            Spacer()

            // Hide checkbox when expanded
            if !isExpanding {
                ZStack {
                    Circle()
                        .fill(item.isChecked ? Color.black : Color(red: 0.851, green: 0.851, blue: 0.851))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .strokeBorder(.white, lineWidth: 1)
                        )

                    if item.isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .overlay(alignment: .center) {
                    Button {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        item.toggleCheck()
                        item.note?.checkIfShouldUncomplete()
                    } label: {
                        Color.clear
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var nameEditingRow: some View {
        HStack {
            Text("Name")
                .font(.outfit(14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            if isEditing {
                TextField("Item name", text: $editedName)
                    .font(.outfit(16))
                    .textFieldStyle(.roundedBorder)
                    .focused($isEditingFocused)
                    .onAppear {
                        editedName = item.name
                        isEditingFocused = true
                    }
                    .onSubmit {
                        onEditComplete(editedName)
                    }
            } else {
                Button {
                    onEditTap()
                } label: {
                    HStack {
                        Text(item.name)
                            .font(.outfit(16))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var quantityRow: some View {
        let quantityValue = Int(item.quantity ?? "1") ?? 1
        let isMinimum = quantityValue <= 1

        return HStack(spacing: 12) {
            Button {
                onQuantityChange(-1)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(isMinimum ? .gray : .blue)
            }
            .buttonStyle(.plain)
            .disabled(isMinimum)

            Text(item.quantity ?? "1")
                .font(.outfit(16))
                .frame(minWidth: 60)

            Button {
                onQuantityChange(1)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 24)
    }

    private var recurringRow: some View {
        HStack {
            Text("Recurring")
                .font(.outfit(14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Spacer()

            Toggle("", isOn: Binding(
                get: { item.isRecurring },
                set: { _ in onToggleRecurring() }
            ))
            .labelsHidden()
        }
    }

    private var seasonalityRow: some View {
        HStack {
            Text("Season")
                .font(.outfit(14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)

            Spacer()

            Picker("", selection: Binding(
                get: { getCurrentSeasonality() },
                set: { onSeasonalityChange($0) }
            )) {
                ForEach(RecurringSeasonality.allCases, id: \.self) { season in
                    Text(season.rawValue).tag(season)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private func getCurrentSeasonality() -> RecurringSeasonality {
        let itemNormalizedName = item.normalizedName
        let descriptor = FetchDescriptor<RecurringItem>(
            predicate: #Predicate { $0.normalizedName == itemNormalizedName }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing.seasonality
        }
        return .allYear
    }

    private func isCurrentUser(_ userId: String) -> Bool {
        FirebaseAuthService.shared.currentUser?.uid == userId
    }
}

struct FloatingAddItemBar: View {
    @Binding var newItemName: String
    @FocusState var isInputFocused: Bool
    @Binding var isRecording: Bool
    let currentTranscription: String
    let onAdd: () -> Void
    let onMicrophoneTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .trailing) {
                ZStack(alignment: .leading) {
                    // Placeholder - left aligned, vertically centered
                    Group {
                        if newItemName.isEmpty && !isRecording {
                            Text("Add item, recipe or meal idea")
                                .foregroundStyle(Color.black.opacity(0.6))
                                .padding(.leading, 24)
                                .padding(.trailing, 56)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeOut(duration: 0.01), value: newItemName.isEmpty)

                    // Recording transcription overlay - shown during recording
                    if isRecording {
                        Text(currentTranscription.isEmpty ? "Listening..." : currentTranscription)
                            .foregroundStyle(currentTranscription.isEmpty ? Color.red.opacity(0.6) : .primary)
                            .padding(.leading, 24)
                            .padding(.trailing, 56)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                    }

                    // Text Editor - left aligned, vertically centered
                    TextEditor(text: $newItemName)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.primary)
                        .scrollContentBackground(.hidden)
                        .scrollDisabled(true)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.asciiCapable)
                        .background(Color.clear)
                        .padding(.leading, 20)
                        .padding(.trailing, 52)
                        .padding(.top, 14)
                        .padding(.bottom, 16)
                        .focused($isInputFocused)
                        .opacity(isRecording ? 0 : 1) // Hide text editor during recording
                        .onChange(of: newItemName) { _, newValue in
                            // Detect Return key by checking for newline
                            if newValue.contains("\n") {
                                // Remove the newline
                                newItemName = newValue.replacingOccurrences(of: "\n", with: "")
                                // Submit
                                onAdd()
                            }
                        }
                }
                .frame(height: 64)

                // Microphone button inside capsule on the right
                VStack {
                    Button {
                        onMicrophoneTap()
                    } label: {
                        ZStack {
                            if isRecording {
                                Circle()
                                    .fill(Color.red.opacity(0.2))
                                    .frame(width: 36, height: 36)
                                    .scaleEffect(isRecording ? 1.2 : 1.0)
                                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isRecording)
                            }
                            Image(systemName: "mic.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(isRecording ? .red : Color.black.opacity(0.4))
                        }
                    }
                    .frame(width: 44, height: 44)
                    .accessibilityLabel(isRecording ? "Stop voice recording" : "Start voice recording")

                    Spacer()
                }
                .padding(.trailing, 8)
                .padding(.top, 10)
            }
            .frame(height: 64)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 40)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 40)
                        .fill(Color.white.opacity(0.85))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 40)
                    .stroke(Color.white, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
            .shadow(color: Color.black.opacity(0.04), radius: 16, x: 0, y: 4)

            if !newItemName.isEmpty {
                Button {
                    onAdd()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.blue)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, isInputFocused ? 8 : 0)
        .animation(.spring(response: 0.3), value: newItemName.isEmpty)
    }
}

struct VoiceInputConfirmationSheet: View {
    let parsedItems: [ParsedIngredient]
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                Text("Add Items to List")
                    .font(.outfit(20, weight: .semiBold))
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                // Items list
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(parsedItems, id: \.name) { item in
                            HStack(spacing: 8) {
                                Text("•")
                                    .font(.outfit(16))
                                Text(item.name)
                                    .font(.outfit(16))
                                if let quantity = item.quantity {
                                    Text("(\(quantity))")
                                        .font(.outfit(15))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                }

                // Actions
                VStack(spacing: 12) {
                    Button {
                        onConfirm()
                        dismiss()
                    } label: {
                        Text("Add All Items")
                            .font(.outfit(17, weight: .semiBold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.black)

                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.outfit(17))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .background(Color(red: 0.941, green: 0.941, blue: 0.937))
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

struct EditItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var item: GroceryItem

    @State private var editedName: String
    @State private var editedQuantity: String

    init(item: GroceryItem) {
        self.item = item
        _editedName = State(initialValue: item.name)
        _editedQuantity = State(initialValue: item.quantity ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Name", text: $editedName)
                    TextField("Quantity", text: $editedQuantity)
                }
            }
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        item.name = editedName
                        item.quantity = editedQuantity.isEmpty ? nil : editedQuantity
                        item.updatedAt = Date()
                        dismiss()
                    }
                    .disabled(editedName.isEmpty)
                }
            }
        }
    }
}

struct EditNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var note: GroceryNote

    @State private var editedTitle: String

    init(note: GroceryNote) {
        self.note = note
        _editedTitle = State(initialValue: note.title)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Note Details") {
                    TextField("Title", text: $editedTitle)
                }
            }
            .navigationTitle("Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        note.title = editedTitle
                        note.updatedAt = Date()
                        dismiss()
                    }
                    .disabled(editedTitle.isEmpty)
                }
            }
        }
    }
}

struct ViewModeSegmentedControl: View {
    @Binding var selectedMode: GroceryNoteDetailView.ViewMode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(GroceryNoteDetailView.ViewMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        selectedMode = mode
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(.outfit(15, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            Group {
                                if selectedMode == mode {
                                    Capsule()
                                        .fill(Color(red: 0.914, green: 0.914, blue: 0.914).opacity(0.6)) // #E9E9E9 at 60%
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(.white, lineWidth: 1)
                                        )
                                        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
                                } else {
                                    Color.clear
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.05)) // #000 at 5% alpha
        )
    }
}

struct InstacartCTAView: View {
    let items: [GroceryItem]

    var body: some View {
        VStack(spacing: 16) {
            // Emoji pile - structured layout
            ZStack {
                ForEach(Array(items.prefix(10).enumerated()), id: \.element.id) { index, item in
                    let position = getEmojiPosition(for: index)
                    IngredientImageView(
                        imageName: item.displayImageName,
                        imageURL: item.customImageURL,
                        emoji: item.emoji,
                        size: 40
                    )
                    .rotationEffect(.degrees(position.rotation))
                    .offset(x: position.x, y: position.y)
                    .zIndex(Double(index))
                }
            }
            .frame(height: 120)

            Text("Order your groceries to be delivered to you")
                .font(.outfit(16))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)

            Link(destination: URL(string: "https://www.instacart.com")!) {
                Text("Order with Instacart")
                    .font(.outfit(16, weight: .semiBold))
                    .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(red: 0.133, green: 0.133, blue: 0.133)) // #222
                )
                .foregroundStyle(.white)
            }
        }
        .padding(16)
    }

    private func getEmojiPosition(for index: Int) -> (x: Double, y: Double, rotation: Double) {
        let spacing: Double = 50 // Horizontal spacing between emojis
        let rowHeight: Double = 48 // Vertical spacing between rows (40 + 8px)

        switch index {
        // Top row (3 emojis)
        case 0: return (x: -spacing, y: -rowHeight, rotation: Double.random(in: -15...15))
        case 1: return (x: 0, y: -rowHeight, rotation: Double.random(in: -15...15))
        case 2: return (x: spacing, y: -rowHeight, rotation: Double.random(in: -15...15))

        // Middle row (4 emojis)
        case 3: return (x: -spacing * 1.5, y: 0, rotation: Double.random(in: -15...15))
        case 4: return (x: -spacing * 0.5, y: 0, rotation: Double.random(in: -15...15))
        case 5: return (x: spacing * 0.5, y: 0, rotation: Double.random(in: -15...15))
        case 6: return (x: spacing * 1.5, y: 0, rotation: Double.random(in: -15...15))

        // Bottom row (3 emojis)
        case 7: return (x: -spacing, y: rowHeight, rotation: Double.random(in: -15...15))
        case 8: return (x: 0, y: rowHeight, rotation: Double.random(in: -15...15))
        case 9: return (x: spacing, y: rowHeight, rotation: Double.random(in: -15...15))

        default: return (x: 0, y: 0, rotation: 0)
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: GroceryNote.self, configurations: config)

    let note = GroceryNote(title: "Test Note")
    container.mainContext.insert(note)

    return NavigationStack {
        GroceryNoteDetailView(note: note)
            .modelContainer(container)
    }
}

// MARK: - Member Management Sheet

struct MemberManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    let members: [String: String]
    let ownerId: String?
    let currentUserId: String?
    let onRemoveMember: (String) -> Void

    private var isCurrentUserOwner: Bool {
        guard let currentUserId, let ownerId else { return false }
        return currentUserId == ownerId
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("People who can view and edit this list.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Members") {
                    ForEach(Array(members.keys), id: \.self) { userId in
                        HStack {
                            // Avatar
                            let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .red]
                            let colorIndex = abs(userId.hashValue) % colors.count
                            let initial = userId.prefix(1).uppercased()

                            Circle()
                                .fill(colors[colorIndex])
                                .frame(width: 40, height: 40)
                                .overlay {
                                    Text(initial)
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(userId == currentUserId ? "You" : userId)
                                    .font(.body)

                                if userId == ownerId {
                                    Text("Owner")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if let role = members[userId] {
                                    Text(role.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            // Remove button (only show if current user is owner and member is not owner)
                            if isCurrentUserOwner && userId != ownerId {
                                Button(role: .destructive) {
                                    onRemoveMember(userId)
                                    dismiss()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Shared With")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed
    }
}

// MARK: - Visual Effect Blur
struct VisualEffectBlur: UIViewRepresentable {
    var blurStyle: UIBlurEffect.Style
    var alpha: CGFloat = 1.0

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
        view.alpha = alpha
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: blurStyle)
        uiView.alpha = alpha
    }
}

// MARK: - RecipeCard

/// Shared recipe card component used across the app
/// - Grocery note meals tab
/// - Root recipes tab
/// - Recipe search results
struct RecipeCard: View {
    let recipe: MealRecipe
    let onTap: () -> Void
    let onDelete: (() -> Void)?

    @State private var showingDeleteConfirmation = false

    init(recipe: MealRecipe, onTap: @escaping () -> Void, onDelete: (() -> Void)? = nil) {
        self.recipe = recipe
        self.onTap = onTap
        self.onDelete = onDelete
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Recipe image
            if let imageURL = recipe.imageURL, let url = URL(string: imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: UIScreen.main.bounds.width / 2 - 32, height: UIScreen.main.bounds.width / 2 - 32)
                            .clipped()
                    case .failure(_):
                        placeholderImage
                    case .empty:
                        loadingImage
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                placeholderImage
            }

            // Recipe info
            VStack(alignment: .leading, spacing: 6) {
                Text(recipe.title)
                    .font(.outfit(15, weight: .semiBold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .font(.system(size: 11))
                        Text("\(recipe.servings)")
                            .font(.outfit(12))
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                        Text("\(recipe.estimatedTimeMinutes)m")
                            .font(.outfit(12))
                    }
                }
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.gray.opacity(0.1), lineWidth: 0.5)
        )
    }

    private var placeholderImage: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: UIScreen.main.bounds.width / 2 - 32, height: UIScreen.main.bounds.width / 2 - 32)
            .overlay {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
            }
    }

    private var loadingImage: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.gray.opacity(0.1), Color.gray.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: UIScreen.main.bounds.width / 2 - 32, height: UIScreen.main.bounds.width / 2 - 32)
            .overlay {
                ProgressView()
            }
    }

    var body: some View {
        cardContent
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                if onDelete != nil {
                    showingDeleteConfirmation = true
                }
            }
            .confirmationDialog("Delete Recipe", isPresented: $showingDeleteConfirmation) {
                Button("Delete Recipe", role: .destructive) {
                    onDelete?()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete \"\(recipe.title)\"?")
            }
    }
}

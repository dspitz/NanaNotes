import SwiftUI
import SwiftData

struct StorageDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var item: GroceryItem

    @State private var isLoadingAI = false
    @State private var errorMessage: String?
    @State private var showingEditMode = false

    @State private var editedStorage: String
    @State private var editedMinDays: String
    @State private var editedMaxDays: String
    @State private var editedPurchasedDate: Date
    @State private var selectedSeasonality: RecurringSeasonality = .allYear

    init(item: GroceryItem) {
        self.item = item
        _editedStorage = State(initialValue: item.storageAdvice ?? "")
        _editedMinDays = State(initialValue: item.shelfLifeDaysMin.map(String.init) ?? "")
        _editedMaxDays = State(initialValue: item.shelfLifeDaysMax.map(String.init) ?? "")
        _editedPurchasedDate = State(initialValue: item.purchasedAt ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    LabeledContent("Name", value: item.name)
                    if let quantity = item.quantity {
                        LabeledContent("Quantity", value: quantity)
                    }
                }

                Section {
                    Toggle("Recurring Item", isOn: Binding(
                        get: { item.isRecurring },
                        set: { newValue in
                            item.isRecurring = newValue
                            updateRecurringItem()
                        }
                    ))

                    if item.isRecurring {
                        Picker("Seasonality", selection: $selectedSeasonality) {
                            ForEach(RecurringSeasonality.allCases, id: \.self) { season in
                                Text(season.rawValue).tag(season)
                            }
                        }
                        .onChange(of: selectedSeasonality) { _, newValue in
                            updateRecurringSeasonality(newValue)
                        }
                    }
                } header: {
                    Text("Recurring Settings")
                } footer: {
                    if item.isRecurring {
                        Text("This item will automatically appear on new grocery lists based on its seasonality.")
                    }
                }

                if showingEditMode {
                    Section("Edit Storage Information") {
                        TextField("Storage Advice", text: $editedStorage, axis: .vertical)
                            .lineLimit(3...6)

                        HStack {
                            TextField("Min Days", text: $editedMinDays)
                                .keyboardType(.numberPad)
                            Text("to")
                            TextField("Max Days", text: $editedMaxDays)
                                .keyboardType(.numberPad)
                        }

                        DatePicker("Purchased Date", selection: $editedPurchasedDate, displayedComponents: .date)
                    }

                    Section {
                        Button("Save Changes") {
                            saveEdits()
                        }
                        .frame(maxWidth: .infinity)

                        Button("Cancel", role: .cancel) {
                            showingEditMode = false
                            resetEdits()
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    // Storage Advice Section
                    Section("Storage Advice") {
                        if isLoadingAI {
                            ShimmerView()
                                .frame(height: 60)
                        } else if let storage = item.storageAdvice {
                            Text(storage)
                        } else {
                            Text("No storage information available")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                    }

                    // Shelf Life Section
                    Section("Shelf Life") {
                        if isLoadingAI {
                            VStack(alignment: .leading, spacing: 8) {
                                ShimmerView()
                                    .frame(height: 20)
                                ShimmerView()
                                    .frame(height: 20)
                            }
                        } else if let shelfLife = item.shelfLifeDescription {
                            LabeledContent("Duration", value: shelfLife)

                            if let source = item.shelfLifeSource {
                                LabeledContent("Source", value: source)
                            }
                        } else {
                            Text("No shelf life information available")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                    }

                    if let purchased = item.purchasedAt {
                        Section("Purchase & Expiration") {
                            LabeledContent("Purchased", value: purchased, format: .dateTime.month().day().year())

                            if let bestBy = item.estimatedBestBy {
                                LabeledContent("Best By", value: bestBy, format: .dateTime.month().day().year())

                                let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: bestBy).day ?? 0
                                if daysRemaining >= 0 {
                                    LabeledContent("Days Remaining", value: "\(daysRemaining)")
                                } else {
                                    Text("Expired \(abs(daysRemaining)) days ago")
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }

                    if item.storageAdvice == nil && !isLoadingAI {
                        Section {
                            Button {
                                fetchStorageInfo()
                            } label: {
                                Label("Retry Fetching Storage Info", systemImage: "arrow.clockwise")
                            }
                            .disabled(!AppConfiguration.isOpenAIConfigured)

                            if !AppConfiguration.isOpenAIConfigured {
                                Text("OpenAI API key not configured")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let error = errorMessage {
                        Section {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }

                    Section {
                        Button {
                            showingEditMode = true
                        } label: {
                            Label("Edit Storage Info", systemImage: "pencil")
                        }
                    }
                }
            }
            .navigationTitle("Storage Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadRecurringSettings()

                // Auto-fetch storage info if not present
                if item.storageAdvice == nil && AppConfiguration.isOpenAIConfigured {
                    fetchStorageInfo()
                }
            }
        }
    }

    private func fetchStorageInfo() {
        guard AppConfiguration.isOpenAIConfigured else { return }

        isLoadingAI = true
        errorMessage = nil

        Task {
            do {
                let service = AIStorageService(apiKey: AppConfiguration.openAIAPIKey)
                let response = try await service.getStorageInfo(for: item.name)

                await MainActor.run {
                    item.storageAdvice = response.storageAdvice
                    item.shelfLifeDaysMin = response.shelfLifeDaysMin
                    item.shelfLifeDaysMax = response.shelfLifeDaysMax
                    item.shelfLifeSource = "AI"
                    item.updatedAt = Date()

                    if let category = GroceryCategory(rawValue: response.categorySuggestion) {
                        item.category = category
                    }

                    let categorizationService = CategorizationService(modelContext: modelContext)
                    Task {
                        try? await categorizationService.saveKnowledge(
                            normalizedName: item.normalizedName,
                            category: item.category,
                            storageAdvice: response.storageAdvice,
                            shelfLifeDaysMin: response.shelfLifeDaysMin,
                            shelfLifeDaysMax: response.shelfLifeDaysMax,
                            source: "AI"
                        )
                    }

                    try? modelContext.save()
                    isLoadingAI = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoadingAI = false
                }
            }
        }
    }

    private func saveEdits() {
        item.storageAdvice = editedStorage.isEmpty ? nil : editedStorage
        item.shelfLifeDaysMin = Int(editedMinDays)
        item.shelfLifeDaysMax = Int(editedMaxDays)
        item.purchasedAt = editedPurchasedDate
        item.shelfLifeSource = "User"

        if let min = item.shelfLifeDaysMin, let max = item.shelfLifeDaysMax {
            let avg = (min + max) / 2
            item.estimatedBestBy = Calendar.current.date(byAdding: .day, value: avg, to: editedPurchasedDate)
        }

        item.updatedAt = Date()
        try? modelContext.save()

        let categorizationService = CategorizationService(modelContext: modelContext)
        Task {
            try? await categorizationService.saveKnowledge(
                normalizedName: item.normalizedName,
                category: item.category,
                storageAdvice: item.storageAdvice,
                shelfLifeDaysMin: item.shelfLifeDaysMin,
                shelfLifeDaysMax: item.shelfLifeDaysMax,
                source: "User"
            )
        }

        showingEditMode = false
    }

    private func resetEdits() {
        editedStorage = item.storageAdvice ?? ""
        editedMinDays = item.shelfLifeDaysMin.map(String.init) ?? ""
        editedMaxDays = item.shelfLifeDaysMax.map(String.init) ?? ""
        editedPurchasedDate = item.purchasedAt ?? Date()
    }

    private func updateRecurringItem() {
        let normalizedName = item.normalizedName

        if item.isRecurring {
            // Find or create recurring item
            let descriptor = FetchDescriptor<RecurringItem>(
                predicate: #Predicate { $0.normalizedName == normalizedName }
            )

            if let existing = try? modelContext.fetch(descriptor).first {
                existing.seasonality = selectedSeasonality
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
                    source: item.shelfLifeSource ?? "User",
                    seasonality: selectedSeasonality
                )
                modelContext.insert(recurringItem)
            }
        } else {
            // Remove recurring item
            let descriptor = FetchDescriptor<RecurringItem>(
                predicate: #Predicate { $0.normalizedName == normalizedName }
            )

            if let existing = try? modelContext.fetch(descriptor).first {
                modelContext.delete(existing)
            }
        }

        try? modelContext.save()
    }

    private func updateRecurringSeasonality(_ seasonality: RecurringSeasonality) {
        let normalizedName = item.normalizedName
        let descriptor = FetchDescriptor<RecurringItem>(
            predicate: #Predicate { $0.normalizedName == normalizedName }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            existing.seasonality = seasonality
            existing.updatedAt = Date()
            try? modelContext.save()
        }
    }

    private func loadRecurringSettings() {
        let normalizedName = item.normalizedName
        let descriptor = FetchDescriptor<RecurringItem>(
            predicate: #Predicate { $0.normalizedName == normalizedName }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            selectedSeasonality = existing.seasonality
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: GroceryItem.self, configurations: config)

    let item = GroceryItem(
        name: "Milk",
        category: .dairy,
        storageAdvice: "Refrigerate at 40°F or below",
        shelfLifeDaysMin: 5,
        shelfLifeDaysMax: 7,
        shelfLifeSource: "Seed"
    )
    container.mainContext.insert(item)

    return StorageDetailView(item: item)
        .modelContainer(container)
}

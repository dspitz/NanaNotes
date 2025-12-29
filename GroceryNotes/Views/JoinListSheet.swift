import SwiftUI

struct JoinListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var shareCode = ""
    @State private var isJoining = false
    @State private var errorMessage: String?

    let syncService = FirestoreSyncService.shared
    let authService = FirebaseAuthService.shared
    let onSuccess: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Enter the 6-digit code shared with you to join a collaborative grocery list.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Share Code") {
                    TextField("000000", text: $shareCode)
                        .keyboardType(.numberPad)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .monospaced()
                        .multilineTextAlignment(.center)
                        .onChange(of: shareCode) { _, newValue in
                            // Limit to 6 digits
                            if newValue.count > 6 {
                                shareCode = String(newValue.prefix(6))
                            }
                        }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        joinList()
                    } label: {
                        if isJoining {
                            HStack {
                                ProgressView()
                                Text("Joining List...")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text("Join List")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(shareCode.count != 6 || isJoining)
                }
            }
            .navigationTitle("Join List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func joinList() {
        guard shareCode.count == 6,
              let userId = authService.currentUser?.uid else { return }

        isJoining = true
        errorMessage = nil

        Task {
            do {
                let listId = try await syncService.joinListWithCode(code: shareCode, userId: userId)
                await MainActor.run {
                    onSuccess(listId)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isJoining = false
                }
            }
        }
    }
}

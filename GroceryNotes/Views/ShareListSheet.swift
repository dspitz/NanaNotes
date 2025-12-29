import SwiftUI

struct ShareListSheet: View {
    @Environment(\.dismiss) private var dismiss
    let note: GroceryNote
    let listId: String

    @State private var shareCode: String?
    @State private var isGeneratingCode = false
    @State private var inviteEmail = ""
    @State private var isSendingInvite = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    let syncService = FirestoreSyncService.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Share this list with family and friends. They'll be able to view and edit items in real-time.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Share with Code") {
                    if let code = shareCode {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Share Code")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(code)
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .monospaced()
                            }

                            Spacer()

                            Button {
                                UIPasteboard.general.string = code
                                successMessage = "Code copied to clipboard"
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.title3)
                            }
                        }

                        Text("Share this 6-digit code. It expires in 24 hours.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            generateShareCode()
                        } label: {
                            if isGeneratingCode {
                                HStack {
                                    ProgressView()
                                    Text("Generating Code...")
                                }
                            } else {
                                Label("Generate Share Code", systemImage: "number")
                            }
                        }
                    }
                }

                Section("Invite by Email") {
                    TextField("Email address", text: $inviteEmail)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)

                    Button {
                        sendInvite()
                    } label: {
                        if isSendingInvite {
                            HStack {
                                ProgressView()
                                Text("Sending...")
                            }
                        } else {
                            Label("Send Invite", systemImage: "envelope")
                        }
                    }
                    .disabled(inviteEmail.isEmpty || isSendingInvite)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if let success = successMessage {
                    Section {
                        Text(success)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Share List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func generateShareCode() {
        isGeneratingCode = true
        errorMessage = nil

        Task {
            do {
                let code = try await syncService.generateShareCode(listId: listId)
                await MainActor.run {
                    shareCode = code
                    isGeneratingCode = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isGeneratingCode = false
                }
            }
        }
    }

    private func sendInvite() {
        guard !inviteEmail.isEmpty else { return }

        isSendingInvite = true
        errorMessage = nil
        successMessage = nil

        Task {
            do {
                try await syncService.shareList(listId: listId, withEmail: inviteEmail)
                await MainActor.run {
                    successMessage = "Invite sent to \(inviteEmail)"
                    inviteEmail = ""
                    isSendingInvite = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSendingInvite = false
                }
            }
        }
    }
}

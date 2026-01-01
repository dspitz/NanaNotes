import SwiftUI

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
    ProfileSheet()
}

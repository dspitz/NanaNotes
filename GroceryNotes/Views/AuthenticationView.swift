import SwiftUI
import AuthenticationServices

struct AuthenticationView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    let authService = FirebaseAuthService.shared

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // Logo
                VStack(spacing: 8) {
                    Image("WhiteNana")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .blendMode(.multiply)

                    Text("Nana Notes")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Collaborative Grocery Lists")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 32)

                // Email/Password Form
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    SecureField("Password", text: $password)
                        .textContentType(isSignUp ? .newPassword : .password)
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        handleEmailAuth()
                    } label: {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(isSignUp ? "Sign Up" : "Sign In")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .disabled(isLoading || email.isEmpty || password.isEmpty)

                    Button {
                        isSignUp.toggle()
                    } label: {
                        Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }
                }
                .padding(.horizontal, 32)

                // Divider
                HStack {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(height: 1)

                    Text("or")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)

                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(height: 1)
                }
                .padding(.horizontal, 32)

                // Apple Sign In
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.email, .fullName]
                } onCompletion: { result in
                    handleAppleSignIn(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 52)
                .padding(.horizontal, 32)

                // Anonymous Sign In (for testing)
                Button {
                    handleAnonymousSignIn()
                } label: {
                    Text("Continue as Guest")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .navigationBarHidden(true)
        }
    }

    private func handleEmailAuth() {
        guard !email.isEmpty, !password.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                print("🔐 Attempting email authentication...")
                if isSignUp {
                    _ = try await authService.signUp(email: email, password: password)
                    print("✅ Sign up successful")
                } else {
                    _ = try await authService.signIn(email: email, password: password)
                    print("✅ Sign in successful")
                }
            } catch {
                print("❌ Email authentication failed: \(error)")
                print("❌ Error details: \(error.localizedDescription)")

                // Provide helpful error messages
                let friendlyMessage: String
                if error.localizedDescription.contains("malformed") || error.localizedDescription.contains("expired") {
                    if isSignUp {
                        friendlyMessage = "Sign up failed. Please check your email format and ensure password is at least 6 characters."
                    } else {
                        friendlyMessage = "Account not found. Try signing up first or use 'Continue as Guest'."
                    }
                } else if error.localizedDescription.contains("network") {
                    friendlyMessage = "Network error. Please check your internet connection."
                } else if error.localizedDescription.contains("password") {
                    friendlyMessage = "Password must be at least 6 characters."
                } else {
                    friendlyMessage = error.localizedDescription
                }

                await MainActor.run {
                    errorMessage = friendlyMessage
                    isLoading = false
                }
            }
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            Task {
                do {
                    _ = try await authService.signInWithApple(authorization: authorization)
                } catch {
                    await MainActor.run {
                        errorMessage = error.localizedDescription
                    }
                }
            }

        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func handleAnonymousSignIn() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                print("🔐 Attempting anonymous sign-in...")
                _ = try await authService.signInAnonymously()
                print("✅ Anonymous sign-in successful")
            } catch {
                print("❌ Anonymous sign-in failed: \(error)")
                print("❌ Error details: \(error.localizedDescription)")
                await MainActor.run {
                    errorMessage = "Sign-in failed: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    AuthenticationView()
}

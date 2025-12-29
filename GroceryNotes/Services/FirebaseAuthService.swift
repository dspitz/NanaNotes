import Foundation
import FirebaseAuth
import AuthenticationServices

@Observable
class FirebaseAuthService {
    static let shared = FirebaseAuthService()

    var currentUser: User?
    var isAuthenticated: Bool { currentUser != nil }

    private init() {
        // Listen for auth state changes
        _ = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.currentUser = user
        }

        // Set current user
        self.currentUser = Auth.auth().currentUser
    }

    // MARK: - Email/Password Authentication

    func signUp(email: String, password: String) async throws -> User {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        return result.user
    }

    func signIn(email: String, password: String) async throws -> User {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        return result.user
    }

    // MARK: - Apple Sign In

    func signInWithApple(authorization: ASAuthorization) async throws -> User {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            throw AuthError.invalidCredential
        }

        guard let appleIDToken = appleIDCredential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            throw AuthError.invalidToken
        }

        let credential = OAuthProvider.credential(
            providerID: AuthProviderID.apple,
            idToken: idTokenString,
            rawNonce: ""
        )

        let result = try await Auth.auth().signIn(with: credential)
        return result.user
    }

    // MARK: - Anonymous Sign In (for testing)

    func signInAnonymously() async throws -> User {
        let result = try await Auth.auth().signInAnonymously()
        return result.user
    }

    // MARK: - Sign Out

    func signOut() throws {
        try Auth.auth().signOut()
    }

    // MARK: - Password Reset

    func sendPasswordReset(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }
}

enum AuthError: LocalizedError {
    case invalidCredential
    case invalidToken

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "Invalid Apple ID credential"
        case .invalidToken:
            return "Invalid identity token"
        }
    }
}

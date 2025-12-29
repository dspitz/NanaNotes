import Foundation
import CloudKit
import SwiftUI

actor CloudKitSharingService {
    func shareNote(_ note: GroceryNote) async throws -> CKShare {
        print("[CloudKit Stub] Would create share for note: \(note.title)")
        throw CloudKitSharingError.notImplemented
    }

    func stopSharing(_ note: GroceryNote) async throws {
        print("[CloudKit Stub] Would stop sharing note: \(note.title)")
    }

    func acceptShare(with metadata: CKShare.Metadata) async throws {
        print("[CloudKit Stub] Would accept share")
    }

    func fetchParticipants(for note: GroceryNote) async throws -> [CKShare.Participant] {
        print("[CloudKit Stub] Would fetch participants for note: \(note.title)")
        return []
    }
}

enum CloudKitSharingError: LocalizedError {
    case notImplemented
    case sharingFailed(Error)
    case notAuthorized

    var errorDescription: String? {
        switch self {
        case .notImplemented:
            return "CloudKit sharing is scaffolded but not fully implemented in V1"
        case .sharingFailed(let error):
            return "Sharing failed: \(error.localizedDescription)"
        case .notAuthorized:
            return "Not authorized to share this note"
        }
    }
}

struct ShareButton: View {
    let note: GroceryNote
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        Button {
            Task {
                do {
                    let service = CloudKitSharingService()
                    _ = try await service.shareNote(note)
                } catch {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .alert("Sharing Not Available", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
}

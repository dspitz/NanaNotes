import SwiftUI
import Combine

struct OutfitFontModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environment(\.font, .outfit(16))
    }
}

extension View {
    func applyOutfitFont() -> some View {
        modifier(OutfitFontModifier())
    }

    func hideTabBarOnKeyboard(_ isKeyboardVisible: Bool) -> some View {
        self.toolbar(isKeyboardVisible ? .hidden : .visible, for: .tabBar)
    }
}

// Observable object to track keyboard visibility
class KeyboardResponder: ObservableObject {
    @Published var isKeyboardVisible = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        let keyboardWillShow = NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .map { _ in true }

        let keyboardWillHide = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .map { _ in false }

        Publishers.Merge(keyboardWillShow, keyboardWillHide)
            .subscribe(on: DispatchQueue.main)
            .assign(to: \.isKeyboardVisible, on: self)
            .store(in: &cancellables)
    }
}

import SwiftUI

#if canImport(UIKit)
import UIKit

struct IPadLandscapeOrientationLock: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear {
                Task { @MainActor in
                    enforceIfNeeded()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                Task { @MainActor in
                    enforceIfNeeded()
                }
            }
    }

    @MainActor
    private func enforceIfNeeded() {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            return
        }

        let preferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .landscape)
        windowScene.requestGeometryUpdate(preferences)
    }
}

extension View {
    func lockIPadToLandscape() -> some View {
        modifier(IPadLandscapeOrientationLock())
    }
}
#else
extension View {
    func lockIPadToLandscape() -> some View {
        self
    }
}
#endif

import SwiftUI

final class DebugSettings: ObservableObject {
    enum GuidanceUIMode {
        case moving
        case arrow
    }

    @Published var showDebugHUD: Bool = false
    @Published var guidanceUIMode: GuidanceUIMode = .moving
}

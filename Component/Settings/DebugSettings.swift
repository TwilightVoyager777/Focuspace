import SwiftUI

final class DebugSettings: ObservableObject {
    enum GuidanceUIMode {
        case moving
        case arrow
        case arrowScope
    }

    @Published var showGuidanceDebugHUD: Bool = false
    @Published var showAICoachDebugHUD: Bool = false
    @Published var guidanceUIMode: GuidanceUIMode = .arrow
    @Published var showGridOverlay: Bool = true
}

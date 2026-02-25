import SwiftUI

struct GuidanceLayeredDotHUDView: View {
    var guidanceOffset: CGSize
    var strength: CGFloat = 0
    var isHolding: Bool = false

    private var clampedStrength: CGFloat {
        min(max(strength, 0), 1)
    }

    var body: some View {
        ZStack {
            BreathingDotView(
                guidanceOffset: guidanceOffset,
                strength: clampedStrength,
                isHolding: isHolding,
                zoomCue: .none,
                tiltCue: 0
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

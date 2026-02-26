import SwiftUI

struct GuidanceLayeredDotHUDView: View {
    var guidanceOffset: CGSize
    var strength: CGFloat = 0
    var isHolding: Bool = false

    var body: some View {
        ZStack {
            MovingTargetMarkerView(
                guidanceOffset: guidanceOffset,
                strength: strength,
                isHolding: isHolding
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct MovingTargetMarkerView: View {
    var guidanceOffset: CGSize
    var strength: CGFloat
    var isHolding: Bool

    private var clampedStrength: CGFloat {
        min(max(strength, 0), 1)
    }

    private var clampedOffset: CGSize {
        GuidanceUIConstants.clampedGuidanceOffset(guidanceOffset)
    }

    var body: some View {
        let ringSize = 16 + clampedStrength * 6
        let opacity = isHolding ? 0.55 : 0.92

        Circle()
            .stroke(Color.white.opacity(opacity), lineWidth: 2.0)
            .frame(width: ringSize, height: ringSize)
            .overlay(
                Circle()
                    .fill(Color.white.opacity(opacity))
                    .frame(width: 3.0, height: 3.0)
            )
            .offset(clampedOffset)
            .animation(
                .interpolatingSpring(stiffness: 140, damping: 18),
                value: clampedOffset
            )
            .allowsHitTesting(false)
    }
}

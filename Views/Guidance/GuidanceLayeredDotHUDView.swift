import SwiftUI

struct GuidanceLayeredDotHUDView: View {
    var guidanceOffset: CGSize
    var strength: CGFloat = 0
    var isHolding: Bool = false

    var body: some View {
        GeometryReader { geo in
            let maxRadiusPx = GuidanceUIConstants.scaledMaxRadius(for: geo.size)

            ZStack {
                MovingTargetMarkerView(
                    guidanceOffset: guidanceOffset,
                    strength: strength,
                    isHolding: isHolding,
                    maxRadiusPx: maxRadiusPx
                )
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct MovingTargetMarkerView: View {
    var guidanceOffset: CGSize
    var strength: CGFloat
    var isHolding: Bool
    var maxRadiusPx: CGFloat = GuidanceUIConstants.defaultMaxRadiusPx

    private var clampedStrength: CGFloat {
        min(max(strength, 0), 1)
    }

    private var clampedOffset: CGSize {
        GuidanceUIConstants.snappedGuidanceOffset(guidanceOffset, maxRadiusPx: maxRadiusPx)
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

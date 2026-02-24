import SwiftUI

struct GuidanceLayeredDotHUDView: View {
    var guidanceOffset: CGSize
    var strength: CGFloat = 0
    var isHolding: Bool = false

    private var clampedStrength: CGFloat {
        min(max(strength, 0), 1)
    }

    var body: some View {
        let dotOffset = GuidanceUIConstants.clampedGuidanceOffset(guidanceOffset)
        let lineOpacity: CGFloat = isHolding ? 0.1 : (0.15 + 0.35 * clampedStrength)

        ZStack {
            GuidanceCrosshairView()
                .opacity(0.9)

            GeometryReader { geo in
                let cx = geo.size.width * 0.5
                let cy = geo.size.height * 0.5
                let center = CGPoint(x: cx, y: cy)
                let target = CGPoint(x: cx + dotOffset.width, y: cy + dotOffset.height)

                Path { path in
                    path.move(to: center)
                    path.addLine(to: target)
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                .opacity(lineOpacity)
            }

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

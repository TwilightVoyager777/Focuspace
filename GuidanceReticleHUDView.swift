import SwiftUI

struct GuidanceReticleHUDView: View {
    var guidanceOffset: CGSize
    var strength: CGFloat = 0
    var isHolding: Bool = false

    private var clampedStrength: CGFloat {
        min(max(strength, 0), 1)
    }

    var body: some View {
        let maxRadius: CGFloat = 40
        let dxPx = guidanceOffset.width * maxRadius
        let dyPx = guidanceOffset.height * maxRadius
        let targetOffset = CGSize(width: dxPx, height: dyPx)
        let arrowOpacity = isHolding ? 0 : (0.25 + 0.75 * clampedStrength)
        let arrowLength = 18 + 18 * clampedStrength
        let angle = atan2(dyPx, dxPx)
        let arrowAnchor = CGPoint(x: dxPx * 0.45, y: dyPx * 0.45)

        ZStack {
            // Layer A — Center Crosshair
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 4, height: 4)

                Path { path in
                    path.move(to: CGPoint(x: -8, y: 0))
                    path.addLine(to: CGPoint(x: -3, y: 0))
                    path.move(to: CGPoint(x: 3, y: 0))
                    path.addLine(to: CGPoint(x: 8, y: 0))
                    path.move(to: CGPoint(x: 0, y: -8))
                    path.addLine(to: CGPoint(x: 0, y: -3))
                    path.move(to: CGPoint(x: 0, y: 3))
                    path.addLine(to: CGPoint(x: 0, y: 8))
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }

            // Layer B — Target Marker (BreathingDotView only)
            BreathingDotView(
                guidanceOffset: .zero,
                strength: clampedStrength,
                isHolding: isHolding,
                zoomCue: .none,
                tiltCue: 0
            )
            .offset(targetOffset)

            // Layer C — Direction Arrow
            Path { path in
                let half = arrowLength / 2
                path.move(to: CGPoint(x: -half, y: 0))
                path.addLine(to: CGPoint(x: half, y: 0))
                path.move(to: CGPoint(x: half, y: 0))
                path.addLine(to: CGPoint(x: half - 6, y: -5))
                path.move(to: CGPoint(x: half, y: 0))
                path.addLine(to: CGPoint(x: half - 6, y: 5))
            }
            .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .opacity((abs(dxPx) < 0.5 && abs(dyPx) < 0.5) ? 0 : arrowOpacity)
            .rotationEffect(.radians(angle))
            .offset(x: arrowAnchor.x, y: arrowAnchor.y)
        }
    }
}

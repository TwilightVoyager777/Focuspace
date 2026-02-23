import SwiftUI

struct ArrowGuidanceHUDView: View {
    var guidanceOffset: CGSize
    var strength: CGFloat = 0
    var isHolding: Bool = false

    private var clampedStrength: CGFloat {
        min(max(strength, 0), 1)
    }

private struct CrosshairView: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.white)
                .frame(width: 18, height: 2)
                .cornerRadius(1)

            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: 18)
                .cornerRadius(1)

            Circle()
                .fill(Color.white)
                .frame(width: 3, height: 3)
        }
    }
}

    var body: some View {
        let maxRadius: CGFloat = GuidanceUIConstants.maxRadiusPx
        let dxPx = guidanceOffset.width * maxRadius
        let dyPx = guidanceOffset.height * maxRadius
        let distance = abs(dxPx) + abs(dyPx)
        let arrowOpacity = isHolding ? 0 : (0.25 + 0.75 * clampedStrength)
        let arrowLength = 14 + 14 * clampedStrength

        ZStack {
            // Target breathing dot (moves)
            BreathingDotView(
                guidanceOffset: guidanceOffset,
                zoomCue: .none,
                tiltCue: 0
            )

            // Arrow from center to target
            GeometryReader { geo in
                let cx = geo.size.width * 0.5
                let cy = geo.size.height * 0.5
                let end = CGPoint(x: cx + dxPx, y: cy + dyPx)

                Path { path in
                    let center = CGPoint(x: cx, y: cy)
                    path.move(to: center)
                    path.addLine(to: end)

                    let angle = atan2(dyPx, dxPx)
                    let headAngle: CGFloat = 0.6
                    let headLength: CGFloat = 6
                    let left = CGPoint(
                        x: end.x - cos(angle - headAngle) * headLength,
                        y: end.y - sin(angle - headAngle) * headLength
                    )
                    let right = CGPoint(
                        x: end.x - cos(angle + headAngle) * headLength,
                        y: end.y - sin(angle + headAngle) * headLength
                    )
                    path.move(to: end)
                    path.addLine(to: left)
                    path.move(to: end)
                    path.addLine(to: right)
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .opacity(distance < 1 ? 0 : arrowOpacity)
            }
            .scaleEffect(arrowLength / 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .overlay(alignment: .center) {
            CrosshairView()
        }
    }
}

import SwiftUI

struct ArrowGuidanceHUDView: View {
    var guidanceOffset: CGSize
    var strength: CGFloat = 0
    var isHolding: Bool = false

    private var clampedStrength: CGFloat {
        min(max(strength, 0), 1)
    }

    var body: some View {
        let displayedOffset = isHolding ? .zero : guidanceOffset
        let clampedOffset = GuidanceUIConstants.clampedGuidanceOffset(displayedOffset)
        let dxPx = clampedOffset.width
        let dyPx = clampedOffset.height
        let distance = sqrt(dxPx * dxPx + dyPx * dyPx)
        let arrowOpacity = isHolding ? 0 : (0.25 + 0.75 * clampedStrength)
        let headLength: CGFloat = 5 + 6 * clampedStrength

        ZStack {
            GuidanceCrosshairView()
                .opacity(0.9)

            // Arrow from center to camera-move target
            GeometryReader { geo in
                let cx = geo.size.width * 0.5
                let cy = geo.size.height * 0.5
                let center = CGPoint(x: cx, y: cy)
                let target = CGPoint(x: cx + dxPx, y: cy + dyPx)

                Path { path in
                    guard distance >= 1 else { return }
                    let ux = (target.x - center.x) / distance
                    let uy = (target.y - center.y) / distance
                    let shaftEnd = CGPoint(
                        x: target.x - ux * headLength,
                        y: target.y - uy * headLength
                    )
                    path.move(to: center)
                    path.addLine(to: shaftEnd)

                    let angle = atan2(target.y - center.y, target.x - center.x)
                    let headAngle: CGFloat = 0.6
                    let left = CGPoint(
                        x: target.x - cos(angle - headAngle) * headLength,
                        y: target.y - sin(angle - headAngle) * headLength
                    )
                    let right = CGPoint(
                        x: target.x - cos(angle + headAngle) * headLength,
                        y: target.y - sin(angle + headAngle) * headLength
                    )
                    path.move(to: target)
                    path.addLine(to: left)
                    path.move(to: target)
                    path.addLine(to: right)
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .opacity(distance < 1 ? 0 : arrowOpacity)
            }

            // Subject dot (moves)
            BreathingDotView(
                guidanceOffset: displayedOffset,
                strength: clampedStrength,
                isHolding: isHolding,
                zoomCue: .none,
                tiltCue: 0
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

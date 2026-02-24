import SwiftUI

struct ArrowReticleHUDView: View {
    var stableDx: CGFloat
    var strength: CGFloat = 0
    var isHolding: Bool = false

    private var clampedStrength: CGFloat {
        min(max(strength, 0), 1)
    }

    private var directionSign: CGFloat {
        stableDx == 0 ? 0 : (stableDx > 0 ? 1 : -1)
    }

    var body: some View {
        let arrowLength = 14 + 14 * clampedStrength
        let arrowOpacity = isHolding ? 0 : (0.25 + 0.75 * clampedStrength)

        ZStack {
            // Center crosshair
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

            // Direction arrow
            ZStack {
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
                .opacity(abs(stableDx) < 0.02 ? 0 : arrowOpacity)
                .rotationEffect(directionSign >= 0 ? .degrees(0) : .degrees(180))
                .offset(x: 0, y: -18)
            }
            .frame(width: 80, height: 80, alignment: .center)
        }
    }
}

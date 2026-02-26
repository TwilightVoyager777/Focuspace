import SwiftUI

struct GuidanceCrosshairView: View {
    var body: some View {
        ZStack {
            Path { path in
                let half: CGFloat = 16
                let seg: CGFloat = 7

                // top-left
                path.move(to: CGPoint(x: -half, y: -half + seg))
                path.addLine(to: CGPoint(x: -half, y: -half))
                path.addLine(to: CGPoint(x: -half + seg, y: -half))

                // top-right
                path.move(to: CGPoint(x: half - seg, y: -half))
                path.addLine(to: CGPoint(x: half, y: -half))
                path.addLine(to: CGPoint(x: half, y: -half + seg))

                // bottom-left
                path.move(to: CGPoint(x: -half, y: half - seg))
                path.addLine(to: CGPoint(x: -half, y: half))
                path.addLine(to: CGPoint(x: -half + seg, y: half))

                // bottom-right
                path.move(to: CGPoint(x: half - seg, y: half))
                path.addLine(to: CGPoint(x: half, y: half))
                path.addLine(to: CGPoint(x: half, y: half - seg))
            }
            .stroke(
                Color.white.opacity(0.95),
                style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
            )

            Circle()
                .fill(Color.white.opacity(0.96))
                .frame(width: 2.2, height: 2.2)
        }
        .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 0)
        .allowsHitTesting(false)
    }
}

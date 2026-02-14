import SwiftUI

struct GridOverlayView: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let thirdWidth = size.width / 3
            let thirdHeight = size.height / 3

            Path { path in
                path.move(to: CGPoint(x: thirdWidth, y: 0))
                path.addLine(to: CGPoint(x: thirdWidth, y: size.height))

                path.move(to: CGPoint(x: thirdWidth * 2, y: 0))
                path.addLine(to: CGPoint(x: thirdWidth * 2, y: size.height))

                path.move(to: CGPoint(x: 0, y: thirdHeight))
                path.addLine(to: CGPoint(x: size.width, y: thirdHeight))

                path.move(to: CGPoint(x: 0, y: thirdHeight * 2))
                path.addLine(to: CGPoint(x: size.width, y: thirdHeight * 2))
            }
            .stroke(Color.white.opacity(0.2), lineWidth: 1)
        }
    }
}

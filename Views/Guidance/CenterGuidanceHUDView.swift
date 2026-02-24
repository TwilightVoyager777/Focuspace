import SwiftUI

struct CenterGuidanceHUDView: View {
    var stableDx: CGFloat
    var strength: CGFloat
    var isHolding: Bool

    @State private var isPulsing = false

    private var clampedStrength: CGFloat {
        min(max(strength, 0), 1)
    }

    private var directionSign: CGFloat {
        stableDx == 0 ? 0 : (stableDx > 0 ? 1 : -1)
    }

    var body: some View {
        ZStack {
            BreathingDotView(
                guidanceOffset: .zero,
                strength: clampedStrength,
                isHolding: isHolding,
                zoomCue: .none,
                tiltCue: 0
            )

            Circle()
                .trim(from: 0.10, to: 0.10 + 0.12 + 0.12 * clampedStrength)
                .stroke(
                    Color.white.opacity(0.6 + 0.4 * clampedStrength),
                    style: StrokeStyle(lineWidth: 1.2 + 1.2 * clampedStrength, lineCap: .round)
                )
                .frame(width: 44 + 12 * clampedStrength, height: 44 + 12 * clampedStrength)
                .opacity(isHolding ? 0 : (0.2 + 0.8 * clampedStrength))
                .rotationEffect(
                    .degrees((directionSign >= 0 ? 20 : -20) + (isPulsing ? 6 : -6))
                )
                .animation(
                    .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                    value: isPulsing
                )
        }
        .onAppear {
            isPulsing = true
        }
    }
}

import SwiftUI

struct GuidanceScopeCrosshairView: View {
    var isHolding: Bool = false
    @State private var isPulsing: Bool = false

    var body: some View {
        ZStack {
            let ringDiameter: CGFloat = 9
            let ringRadius: CGFloat = ringDiameter * 0.5
            let segmentLength: CGFloat = 6
            let lineThickness: CGFloat = 2.8
            let offsetToSegmentCenter = ringRadius + segmentLength * 0.5
            let ringScale: CGFloat = isHolding ? (isPulsing ? 1.06 : 0.98) : 1.0
            let ringOpacity: CGFloat = isHolding ? (isPulsing ? 1.0 : 0.86) : 0.99

            Circle()
                .stroke(Color.white.opacity(ringOpacity), lineWidth: 2.8)
                .frame(width: ringDiameter, height: ringDiameter)
                .scaleEffect(ringScale)

            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.99))
                .frame(width: segmentLength, height: lineThickness)
                .offset(x: -offsetToSegmentCenter, y: 0)

            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.99))
                .frame(width: segmentLength, height: lineThickness)
                .offset(x: offsetToSegmentCenter, y: 0)

            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.99))
                .frame(width: lineThickness, height: segmentLength)
                .offset(x: 0, y: -offsetToSegmentCenter)

            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.99))
                .frame(width: lineThickness, height: segmentLength)
                .offset(x: 0, y: offsetToSegmentCenter)
        }
        .frame(width: 32, height: 32)
        .shadow(color: .black.opacity(0.30), radius: 1.2, x: 0, y: 0)
        .allowsHitTesting(false)
        .onAppear {
            if isHolding {
                startPulseIfNeeded()
            }
        }
        .onChange(of: isHolding) { _, holding in
            if holding {
                startPulseIfNeeded()
            } else {
                isPulsing = false
            }
        }
    }

    private func startPulseIfNeeded() {
        guard isPulsing == false else { return }
        withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
    }
}

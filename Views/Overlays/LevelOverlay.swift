import CoreMotion
import SwiftUI

final class LevelMotionManager: ObservableObject {
    @Published var pitch: Double = 0
    @Published var roll: Double = 0

    private let motionManager = CMMotionManager()

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.pitch = motion.attitude.pitch
            self.roll = motion.attitude.roll
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }
}

struct LevelOverlay: View {
    static var isSupported: Bool {
        CMMotionManager().isDeviceMotionAvailable
    }

    let isEnabled: Bool

    @StateObject private var motion = LevelMotionManager()

    var body: some View {
        GeometryReader { proxy in
            if isEnabled {
                let size = proxy.size
                let maxOffset = min(size.height, size.width) * 0.2
                let pitchOffset = CGFloat(motion.pitch) * maxOffset
                let rollAngle = Angle(radians: motion.roll)

                ZStack {
                    Circle()
                        .stroke(Color.yellow.opacity(0.6), lineWidth: 1)
                        .frame(width: 10, height: 10)

                    Rectangle()
                        .fill(Color.yellow.opacity(0.85))
                        .frame(width: min(size.width * 0.7, 240), height: 2)
                        .rotationEffect(rollAngle)
                        .offset(y: max(-maxOffset, min(maxOffset, pitchOffset)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            if isEnabled {
                motion.start()
            }
        }
        .onChange(of: isEnabled) { _, newValue in
            if newValue {
                motion.start()
            } else {
                motion.stop()
            }
        }
        .onDisappear {
            motion.stop()
        }
    }
}

import CoreMotion
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

final class LevelMotionManager: ObservableObject {
    @Published var gravityX: Double = 0
    @Published var gravityY: Double = 0
    @Published var gravityZ: Double = 0

    private let motionManager = CMMotionManager()

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.gravityX = motion.gravity.x
            self.gravityY = motion.gravity.y
            self.gravityZ = motion.gravity.z
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
    @State private var baselineHorizontal: CGFloat = 0
    @State private var baselineVertical: CGFloat = 0
    @State private var hasCalibrationBaseline: Bool = false

    var body: some View {
        GeometryReader { proxy in
            if isEnabled {
                let size = proxy.size
                let screenAxes = screenLevelAxes(
                    gravityX: motion.gravityX,
                    gravityY: motion.gravityY,
                    gravityZ: motion.gravityZ
                )
                let calibratedHorizontal = screenAxes.horizontal - baselineHorizontal
                let rollAngle = Angle(radians: calibratedHorizontal * (.pi / 3.0))

                ZStack {
                    Circle()
                        .stroke(Color.yellow.opacity(0.6), lineWidth: 1)
                        .frame(width: 10, height: 10)

                    Rectangle()
                        .fill(Color.yellow.opacity(0.85))
                        .frame(width: min(size.width * 0.7, 240), height: 2)
                        .rotationEffect(rollAngle)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            if isEnabled {
                resetCalibration()
                motion.start()
            }
        }
        .onChange(of: isEnabled) { _, newValue in
            if newValue {
                resetCalibration()
                motion.start()
            } else {
                motion.stop()
                resetCalibration()
            }
        }
        .onChange(of: motion.gravityX) { _, _ in
            calibrateIfNeeded()
        }
        .onChange(of: motion.gravityY) { _, _ in
            calibrateIfNeeded()
        }
        .onChange(of: motion.gravityZ) { _, _ in
            calibrateIfNeeded()
        }
        .onDisappear {
            motion.stop()
            resetCalibration()
        }
    }

    private func screenLevelAxes(
        gravityX: Double,
        gravityY: Double,
        gravityZ: Double
    ) -> (horizontal: CGFloat, vertical: CGFloat) {
        let gx = CGFloat(gravityX)
        let gy = CGFloat(gravityY)
        let gz = CGFloat(gravityZ)

        let orientation = currentInterfaceOrientation()
        let horizontal: CGFloat
        let vertical: CGFloat

        switch orientation {
        case .landscapeLeft:
            horizontal = -gy
            vertical = -gx
        case .landscapeRight:
            horizontal = gy
            vertical = gx
        case .portraitUpsideDown:
            horizontal = -gx
            vertical = gy
        default:
            horizontal = gx
            vertical = -gy
        }

        // Reduce sensitivity when the device is close to flat to avoid jumpy
        // readings caused by weak horizontal gravity components.
        let uprightFactor = max(0.35, min(1.0, 1.0 - abs(gz) * 0.55))
        return (horizontal * uprightFactor, vertical * uprightFactor)
    }

    private func currentInterfaceOrientation() -> UIInterfaceOrientation {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let active = scenes.first(where: { $0.activationState == .foregroundActive }) {
            return active.interfaceOrientation
        }
        return scenes.first?.interfaceOrientation ?? .portrait
        #else
        return .portrait
        #endif
    }

    private func calibrateIfNeeded() {
        guard isEnabled, !hasCalibrationBaseline else { return }
        let magnitude = abs(motion.gravityX) + abs(motion.gravityY) + abs(motion.gravityZ)
        guard magnitude > 0.05 else { return }

        let screenAxes = screenLevelAxes(
            gravityX: motion.gravityX,
            gravityY: motion.gravityY,
            gravityZ: motion.gravityZ
        )
        baselineHorizontal = screenAxes.horizontal
        baselineVertical = 0
        hasCalibrationBaseline = true
    }

    private func resetCalibration() {
        baselineHorizontal = 0
        baselineVertical = 0
        hasCalibrationBaseline = false
    }
}

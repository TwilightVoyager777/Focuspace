import SwiftUI

// 快门按钮
struct ShutterButtonView: View {
    @ObservedObject var cameraController: CameraSessionController
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.black.opacity(0.6), lineWidth: 6)
                    .frame(width: 86, height: 86)

                if cameraController.captureMode == .video {
                    if cameraController.isRecording {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.red)
                            .frame(width: 40, height: 40)
                    } else {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 72, height: 72)
                    }
                } else {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 72, height: 72)
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: cameraController.isRecording)
        .animation(.easeInOut(duration: 0.2), value: cameraController.captureMode)
    }
}

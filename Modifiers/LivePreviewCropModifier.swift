import SwiftUI
import AVFoundation

// 三等分网格线
struct LivePreviewCropModifier: ViewModifier {
    let cameraPosition: AVCaptureDevice.Position
    let captureMode: CameraSessionController.CaptureMode

    func body(content: Content) -> some View {
        _ = cameraPosition
        _ = captureMode
        let horizontalScale: CGFloat = 1.0
        return content
            .scaleEffect(x: horizontalScale, y: 1.0, anchor: .center)
            .clipped()
    }
}

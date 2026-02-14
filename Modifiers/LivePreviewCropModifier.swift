import SwiftUI
import AVFoundation

// 三等分网格线
struct LivePreviewCropModifier: ViewModifier {
    let cameraPosition: AVCaptureDevice.Position
    let captureMode: CameraSessionController.CaptureMode

    func body(content: Content) -> some View {
        let cropX: CGFloat
        if cameraPosition == .front {
            cropX = (captureMode == .photo) ? 1.30 : 1.0
        } else {
            cropX = 1.0
        }
        return content
            .scaleEffect(x: cropX, y: 1.0, anchor: .center)
            .clipped()
    }
}

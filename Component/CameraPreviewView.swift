import AVFoundation
import SwiftUI

// SwiftUI wrapper for AVCaptureVideoPreviewLayer.
// 使用 SwiftUI 包装相机预览层，让 SwiftUI 直接显示相机画面。
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
    }
}

// Backing UIView that hosts AVCaptureVideoPreviewLayer.
// 提供真正的预览层容器，SwiftUI 通过它显示相机画面。
final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as? AVCaptureVideoPreviewLayer ?? AVCaptureVideoPreviewLayer()
    }
}

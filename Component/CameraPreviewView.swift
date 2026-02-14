@preconcurrency import AVFoundation
import SwiftUI

// SwiftUI 桥接：用 AVCaptureVideoPreviewLayer 显示相机画面
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let isFrontCamera: Bool
    let previewFreeze: Bool
    @Binding var connection: AVCaptureConnection?
    let onPreviewView: (PreviewView) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        configureConnection(view.videoPreviewLayer.connection)
        updateConnectionBinding(view.videoPreviewLayer.connection, context: context)
        context.coordinator.lastIsFront = isFrontCamera
        onPreviewView(view)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
        if context.coordinator.lastIsFront != isFrontCamera {
            context.coordinator.lastIsFront = isFrontCamera
            configureConnection(uiView.videoPreviewLayer.connection)
        }
        uiView.videoPreviewLayer.connection?.isEnabled = !previewFreeze
        updateConnectionBinding(uiView.videoPreviewLayer.connection, context: context)
        onPreviewView(uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func configureConnection(_ connection: AVCaptureConnection?) {
        guard let connection else { return }
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = isFrontCamera
        }
    }

    private func updateConnectionBinding(_ newConnection: AVCaptureConnection?, context: Context) {
        guard context.coordinator.lastConnection !== newConnection else { return }
        context.coordinator.lastConnection = newConnection
        Task { @MainActor in
            await Task.yield()
            connection = newConnection
        }
    }

    final class Coordinator {
        var lastIsFront: Bool? = nil
        var lastConnection: AVCaptureConnection? = nil
    }
}

// 预览层容器
final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as? AVCaptureVideoPreviewLayer ?? AVCaptureVideoPreviewLayer()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        clipsToBounds = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer.frame = bounds
    }

    func snapshotImage() -> UIImage? {
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { ctx in
            layer.render(in: ctx.cgContext)
        }
    }
}

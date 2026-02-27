@preconcurrency import AVFoundation
import SwiftUI
import UIKit

// SwiftUI 桥接：用 AVCaptureVideoPreviewLayer 显示相机画面
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let isFrontCamera: Bool
    let previewFreeze: Bool
    let onPreviewView: (PreviewView) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        configureConnection(view.videoPreviewLayer.connection)
        context.coordinator.lastIsFront = isFrontCamera
        onPreviewView(view)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
        // Keep preview orientation in sync with interface orientation.
        configureConnection(uiView.videoPreviewLayer.connection)
        if context.coordinator.lastIsFront != isFrontCamera {
            context.coordinator.lastIsFront = isFrontCamera
            configureConnection(uiView.videoPreviewLayer.connection)
        }
        uiView.videoPreviewLayer.connection?.isEnabled = !previewFreeze
        onPreviewView(uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func configureConnection(_ connection: AVCaptureConnection?) {
        guard let connection else { return }
        applyInterfaceRotation(to: connection)
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = isFrontCamera
        }
    }

    private func applyInterfaceRotation(to connection: AVCaptureConnection) {
        let angle = currentInterfaceVideoRotationAngle()
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    private func currentInterfaceVideoRotationAngle() -> CGFloat {
        let deviceOrientation = UIDevice.current.orientation
        switch deviceOrientation {
        case .landscapeLeft:
            return 0
        case .landscapeRight:
            return 180
        case .portraitUpsideDown:
            return 270
        default:
            break
        }

        let interfaceOrientation = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .interfaceOrientation

        switch interfaceOrientation {
        case .landscapeRight:
            return 0
        case .landscapeLeft:
            return 180
        case .portraitUpsideDown:
            return 270
        default:
            return 90
        }
    }

    final class Coordinator {
        var lastIsFront: Bool? = nil
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

    // 预览层当前可见区域，转换为 0...1 的输出归一化坐标
    func visibleMetadataOutputRect() -> CGRect {
        let rect = videoPreviewLayer.metadataOutputRectConverted(fromLayerRect: bounds)
        return rect.standardized
    }
}

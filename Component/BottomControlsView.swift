import SwiftUI

// 底部快门区域（左缩略图 + 中快门 + 右切换）
struct BottomControlsView: View {
    let cameraController: CameraSessionController
    let latestThumbnail: UIImage?
    let usePadPortraitLayout: Bool
    let onToggleBottomPanel: () -> Void
    let onSmartCompose: () -> Void

    var body: some View {
        let controlScale: CGFloat = usePadPortraitLayout ? 1.06 : 1.0
        let sideButtonSpacing: CGFloat = usePadPortraitLayout ? 10 : 8

        ZStack {
            // 左右按钮占位，使用 Spacer 推到两侧
            HStack {
                RecentThumbnailView(latestThumbnail: latestThumbnail)
                    .scaleEffect(controlScale)

                Spacer()

                HStack(spacing: sideButtonSpacing) {
                    SmartComposeButtonView(
                        isActive: cameraController.isSmartComposeActive,
                        isProcessing: cameraController.isSmartComposeProcessing,
                        action: onSmartCompose
                    )
                    TemplateToggleButtonView(action: onToggleBottomPanel)
                }
                .scaleEffect(controlScale)
            }

            // 中间快门按钮叠加，保证始终居中
            ShutterButtonView(cameraController: cameraController) {
                if cameraController.captureMode == .photo {
                    cameraController.capturePhoto()
                } else {
                    cameraController.toggleRecording()
                }
            }
            .scaleEffect(controlScale)
        }
    }
}

private struct SmartComposeButtonView: View {
    let isActive: Bool
    let isProcessing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill((isActive || isProcessing) ? Color.white.opacity(0.20) : Color.white.opacity(0.10))
                    .frame(width: 38, height: 38)
                Image(systemName: isActive ? "viewfinder.circle.fill" : "viewfinder.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .opacity(isProcessing ? 0.95 : 1.0)
        .buttonStyle(.plain)
    }
}

import SwiftUI

// 底部快门区域（左缩略图 + 中快门 + 右切换）
struct BottomControlsView: View {
    let cameraController: CameraSessionController
    let latestThumbnail: UIImage?
    let usePadPortraitLayout: Bool
    var useLandscapeSidebarLayout: Bool = false
    let onToggleBottomPanel: () -> Void
    let onSmartCompose: () -> Void

    var body: some View {
        let controlScale: CGFloat = usePadPortraitLayout ? 1.06 : 1.0
        let sideButtonSpacing: CGFloat = usePadPortraitLayout ? 10 : 8

        Group {
            if useLandscapeSidebarLayout {
                // iPad landscape right rail: keep utility controls clustered around shutter.
                VStack(spacing: 12) {
                    VStack(spacing: 10) {
                        TemplateToggleButtonView(action: onToggleBottomPanel)

                        SmartComposeButtonView(
                            isActive: cameraController.isSmartComposeActive,
                            isProcessing: cameraController.isSmartComposeProcessing,
                            size: 49,
                            action: onSmartCompose
                        )
                    }
                    .scaleEffect(0.94)

                    ShutterButtonView(cameraController: cameraController) {
                        if cameraController.captureMode == .photo {
                            cameraController.capturePhoto()
                        } else {
                            cameraController.toggleRecording()
                        }
                    }
                    .scaleEffect(0.9)

                    RecentThumbnailView(latestThumbnail: latestThumbnail)
                        .scaleEffect(0.93)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.vertical, 6)
            } else {
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
    }
}

private struct SmartComposeButtonView: View {
    let isActive: Bool
    let isProcessing: Bool
    var size: CGFloat = 38
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill((isActive || isProcessing) ? Color.white.opacity(0.20) : Color.white.opacity(0.10))
                    .frame(width: size, height: size)
                Image(systemName: isActive ? "viewfinder.circle.fill" : "viewfinder.circle")
                    .font(.system(size: size * 0.47, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .opacity(isProcessing ? 0.95 : 1.0)
        .buttonStyle(.plain)
    }
}

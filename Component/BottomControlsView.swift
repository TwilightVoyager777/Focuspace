import SwiftUI

// 底部快门区域（左缩略图 + 中快门 + 右切换）
struct BottomControlsView: View {
    let cameraController: CameraSessionController
    let latestThumbnail: UIImage?
    let onToggleBottomPanel: () -> Void

    var body: some View {
        ZStack {
            // 左右按钮占位，使用 Spacer 推到两侧
            HStack {
                RecentThumbnailView(latestThumbnail: latestThumbnail)

                Spacer()

                TemplateToggleButtonView(action: onToggleBottomPanel)
            }

            // 中间快门按钮叠加，保证始终居中
            ShutterButtonView(cameraController: cameraController) {
                if cameraController.captureMode == .photo {
                    cameraController.capturePhoto()
                } else {
                    cameraController.toggleRecording()
                }
            }
        }
    }
}

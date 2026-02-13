import SwiftUI

// 底部控制区域
struct BottomBarView: View {
    let height: CGFloat
    let cameraController: CameraSessionController
    let latestThumbnail: UIImage?

    var body: some View {
        ZStack {
            // 底部区域背景
            Color.black

            VStack(spacing: 18) {
                // 工具条（可横向滚动）
                BottomC1ToolsRowView(cameraController: cameraController)
                // 下方控制行：缩略图 + 快门 + 切换镜头
                BottomControlsView(
                    cameraController: cameraController,
                    latestThumbnail: latestThumbnail
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }
}

// 底部快门区域（左缩略图 + 中快门 + 右切换）
struct BottomControlsView: View {
    let cameraController: CameraSessionController
    let latestThumbnail: UIImage?

    var body: some View {
        ZStack {
            // 左右按钮占位，使用 Spacer 推到两侧
            HStack {
                RecentThumbnailView(latestThumbnail: latestThumbnail)

                Spacer()

                CameraSwitchButtonView()
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

// 左侧最近缩略图
struct RecentThumbnailView: View {
    let latestThumbnail: UIImage?

    var body: some View {
        NavigationLink {
            MediaLibraryView()
        } label: {
            ZStack {
                if let image = latestThumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.white.opacity(0.2)
                }
            }
            .frame(width: 49, height: 49)
            .clipShape(Circle())
            .overlay(
                Circle().stroke(Color.white.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// 右侧镜头切换按钮
struct CameraSwitchButtonView: View {
    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath.camera")
            .font(.system(size: 22, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 49, height: 49)
    }
}

import SwiftUI

// 顶部状态栏区域
struct TopBarView: View {
    let height: CGFloat
    @ObservedObject var cameraController: CameraSessionController
    let onSelectTemplate: (String) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            // 顶部区域背景
            Color.black

            // 顶部内容在 TopBar 内部垂直居中
            VStack(alignment: .center, spacing: 0) {
                Spacer()

                ZStack {
                    HStack {
                        // 闪光灯按钮（循环切换模式）
                        Button {
                            cameraController.cycleFlashMode()
                        } label: {
                            CircularIconButtonView(systemName: flashIconName)
                        }
                        .disabled(!cameraController.isFlashSupported || cameraController.captureMode == .video)
                        .opacity(cameraController.isFlashSupported && cameraController.captureMode == .photo ? 1.0 : 0.4)

                        Spacer()

                        NavigationLink {
                            SettingsView(onSelectTemplate: onSelectTemplate)
                        } label: {
                            CircularIconButtonView(systemName: "ellipsis")
                        }
                        .buttonStyle(.plain)
                    }

                    // 中间分段控件固定居中，不受左右宽度影响
                    SegmentedModeView(
                        captureMode: cameraController.captureMode,
                        onSelect: { mode in
                            cameraController.setCaptureMode(mode)
                        }
                    )
                }
                .padding(.horizontal, 16)

                Spacer()
            }

        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }

    private var flashIconName: String {
        guard cameraController.isFlashSupported, cameraController.captureMode == .photo else {
            return "bolt.slash"
        }
        switch cameraController.flashMode {
        case .off:
            return "bolt.slash"
        case .on:
            return "bolt.fill"
        case .auto:
            return "bolt.badge.a"
        }
    }
}

// 顶部分段控件（视频 / 照片）
struct SegmentedModeView: View {
    let captureMode: CameraSessionController.CaptureMode
    let onSelect: (CameraSessionController.CaptureMode) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button {
                onSelect(.video)
            } label: {
                Text("Video")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(captureMode == .video ? .white : .white.opacity(0.6))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(captureMode == .video ? Color.black.opacity(0.6) : Color.clear)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)

            Button {
                onSelect(.photo)
            } label: {
                Text("Photo")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(captureMode == .photo ? .white : .white.opacity(0.6))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(captureMode == .photo ? Color.black.opacity(0.6) : Color.clear)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.white.opacity(0.18))
        .cornerRadius(14)
    }
}

// 顶部圆形图标按钮
struct CircularIconButtonView: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 32, height: 32)
            .background(Color.white.opacity(0.15))
            .clipShape(Circle())
    }
}

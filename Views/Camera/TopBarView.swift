import SwiftUI

// 顶部状态栏区域
struct TopBarView: View {
    let height: CGFloat
    @ObservedObject var cameraController: CameraSessionController
    let usePadPortraitLayout: Bool
    let onSelectTemplate: (String) -> Void

    var body: some View {
        let barBackground = usePadPortraitLayout ? Color.clear : Color.black

        ZStack(alignment: .top) {
            // 顶部区域背景
            barBackground

            // 顶部内容在 TopBar 内部垂直居中
            VStack(alignment: .center, spacing: 0) {
                Spacer()

                ZStack {
                    HStack {
                        // 闪光灯按钮（循环切换模式）
                        Button {
                            cameraController.cycleFlashMode()
                        } label: {
                            CircularIconButtonView(
                                systemName: flashIconName,
                                usePadPortraitLayout: usePadPortraitLayout
                            )
                        }
                        .disabled(!cameraController.isFlashSupported || cameraController.captureMode == .video)
                        .opacity(cameraController.isFlashSupported && cameraController.captureMode == .photo ? 1.0 : 0.4)

                        Spacer()

                        NavigationLink {
                            SettingsView(onSelectTemplate: onSelectTemplate)
                        } label: {
                            CircularIconButtonView(
                                systemName: "ellipsis",
                                usePadPortraitLayout: usePadPortraitLayout
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // 中间分段控件固定居中，不受左右宽度影响
                    SegmentedModeView(
                        captureMode: cameraController.captureMode,
                        usePadPortraitLayout: usePadPortraitLayout,
                        onSelect: { mode in
                            cameraController.setCaptureMode(mode)
                        }
                    )
                }
                .padding(.horizontal, usePadPortraitLayout ? 18 : 16)

                Spacer()
            }

        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(barBackground)
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
    let usePadPortraitLayout: Bool
    let onSelect: (CameraSessionController.CaptureMode) -> Void

    var body: some View {
        let labelFontSize: CGFloat = usePadPortraitLayout ? 14 : 12
        let horizontalPadding: CGFloat = usePadPortraitLayout ? 14 : 12
        let verticalPadding: CGFloat = usePadPortraitLayout ? 8 : 6
        let segmentCornerRadius: CGFloat = usePadPortraitLayout ? 11 : 10
        let containerVerticalPadding: CGFloat = usePadPortraitLayout ? 5 : 4
        let containerHorizontalPadding: CGFloat = usePadPortraitLayout ? 10 : 8
        let containerCornerRadius: CGFloat = usePadPortraitLayout ? 16 : 14

        HStack(spacing: 6) {
            Button {
                onSelect(.video)
            } label: {
                Text("Video")
                    .font(.system(size: labelFontSize, weight: .semibold))
                    .foregroundColor(captureMode == .video ? .white : .white.opacity(0.6))
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                    .background(captureMode == .video ? Color.black.opacity(0.6) : Color.clear)
                    .cornerRadius(segmentCornerRadius)
            }
            .buttonStyle(.plain)

            Button {
                onSelect(.photo)
            } label: {
                Text("Photo")
                    .font(.system(size: labelFontSize, weight: .bold))
                    .foregroundColor(captureMode == .photo ? .white : .white.opacity(0.6))
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                    .background(captureMode == .photo ? Color.black.opacity(0.6) : Color.clear)
                    .cornerRadius(segmentCornerRadius)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, containerVerticalPadding)
        .padding(.horizontal, containerHorizontalPadding)
        .background(Color.white.opacity(0.18))
        .cornerRadius(containerCornerRadius)
    }
}

// 顶部圆形图标按钮
struct CircularIconButtonView: View {
    let systemName: String
    var usePadPortraitLayout: Bool = false

    var body: some View {
        let iconSize: CGFloat = usePadPortraitLayout ? 16 : 14
        let frameSize: CGFloat = usePadPortraitLayout ? 36 : 32

        Image(systemName: systemName)
            .font(.system(size: iconSize, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: frameSize, height: frameSize)
            .background(Color.white.opacity(0.15))
            .clipShape(Circle())
    }
}

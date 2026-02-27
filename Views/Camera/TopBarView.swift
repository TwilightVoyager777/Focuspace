import SwiftUI

// 顶部状态栏区域
struct TopBarView: View {
    let height: CGFloat
    @ObservedObject var cameraController: CameraSessionController
    let usePadPortraitLayout: Bool
    var useLandscapeSidebarLayout: Bool = false
    let onSelectTemplate: (String) -> Void

    var body: some View {
        let useLargeControls = usePadPortraitLayout || useLandscapeSidebarLayout
        let barBackground: Color = {
            if useLandscapeSidebarLayout {
                return Color.clear
            }
            return usePadPortraitLayout ? Color.clear : Color.black
        }()

        ZStack(alignment: .top) {
            // 顶部区域背景
            barBackground

            if useLandscapeSidebarLayout {
                // iPad landscape left rail: compact centered vertical block.
                VStack(spacing: 16) {
                    VStack(spacing: 14) {
                        NavigationLink {
                            SettingsView(onSelectTemplate: onSelectTemplate)
                        } label: {
                            CircularIconButtonView(
                                systemName: "ellipsis",
                                usePadPortraitLayout: useLargeControls
                            )
                        }
                        .buttonStyle(.plain)

                        SegmentedModeView(
                            captureMode: cameraController.captureMode,
                            usePadPortraitLayout: useLargeControls,
                            useVerticalLayout: true,
                            useSymbolLabels: true,
                            onSelect: { mode in
                                cameraController.setCaptureMode(mode)
                            }
                        )

                        Button {
                            cameraController.cycleFlashMode()
                        } label: {
                            CircularIconButtonView(
                                systemName: flashIconName,
                                usePadPortraitLayout: useLargeControls
                            )
                        }
                        .disabled(!cameraController.isFlashSupported || cameraController.captureMode == .video)
                        .opacity(cameraController.isFlashSupported && cameraController.captureMode == .photo ? 1.0 : 0.4)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.horizontal, 10)
            } else {
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
                                    usePadPortraitLayout: useLargeControls
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
                                    usePadPortraitLayout: useLargeControls
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        // 中间分段控件固定居中，不受左右宽度影响
                        SegmentedModeView(
                            captureMode: cameraController.captureMode,
                            usePadPortraitLayout: useLargeControls,
                            onSelect: { mode in
                                cameraController.setCaptureMode(mode)
                            }
                        )
                    }
                    .padding(.horizontal, usePadPortraitLayout ? 18 : 16)

                    Spacer()
                }
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
    var useVerticalLayout: Bool = false
    var useSymbolLabels: Bool = false
    let onSelect: (CameraSessionController.CaptureMode) -> Void

    var body: some View {
        let labelFontSize: CGFloat = usePadPortraitLayout ? 14 : 12
        let horizontalPadding: CGFloat = usePadPortraitLayout ? 14 : 12
        let verticalPadding: CGFloat = usePadPortraitLayout ? 8 : 6
        let segmentCornerRadius: CGFloat = usePadPortraitLayout ? 11 : 10
        let containerVerticalPadding: CGFloat = usePadPortraitLayout ? 5 : 4
        let containerHorizontalPadding: CGFloat = usePadPortraitLayout ? 10 : 8
        let containerCornerRadius: CGFloat = usePadPortraitLayout ? 16 : 14

        Group {
            if useVerticalLayout {
                VStack(spacing: 6) {
                    segmentButton(
                        title: "Video",
                        systemName: "video.fill",
                        mode: .video,
                        weight: .semibold,
                        labelFontSize: labelFontSize,
                        horizontalPadding: horizontalPadding,
                        verticalPadding: verticalPadding,
                        segmentCornerRadius: segmentCornerRadius
                    )

                    segmentButton(
                        title: "Photo",
                        systemName: "camera.fill",
                        mode: .photo,
                        weight: .bold,
                        labelFontSize: labelFontSize,
                        horizontalPadding: horizontalPadding,
                        verticalPadding: verticalPadding,
                        segmentCornerRadius: segmentCornerRadius
                    )
                }
            } else {
                HStack(spacing: 6) {
                    segmentButton(
                        title: "Video",
                        systemName: "video.fill",
                        mode: .video,
                        weight: .semibold,
                        labelFontSize: labelFontSize,
                        horizontalPadding: horizontalPadding,
                        verticalPadding: verticalPadding,
                        segmentCornerRadius: segmentCornerRadius
                    )

                    segmentButton(
                        title: "Photo",
                        systemName: "camera.fill",
                        mode: .photo,
                        weight: .bold,
                        labelFontSize: labelFontSize,
                        horizontalPadding: horizontalPadding,
                        verticalPadding: verticalPadding,
                        segmentCornerRadius: segmentCornerRadius
                    )
                }
            }
        }
        .padding(.vertical, containerVerticalPadding)
        .padding(.horizontal, containerHorizontalPadding)
        .background(Color.white.opacity(0.18))
        .cornerRadius(containerCornerRadius)
    }

    @ViewBuilder
    private func segmentButton(
        title: String,
        systemName: String,
        mode: CameraSessionController.CaptureMode,
        weight: Font.Weight,
        labelFontSize: CGFloat,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat,
        segmentCornerRadius: CGFloat
    ) -> some View {
        Button {
            onSelect(mode)
        } label: {
            Group {
                if useSymbolLabels {
                    Image(systemName: systemName)
                        .font(.system(size: labelFontSize + 1, weight: .semibold))
                } else {
                    Text(title)
                        .font(.system(size: labelFontSize, weight: weight))
                }
            }
                .foregroundColor(captureMode == mode ? .white : .white.opacity(0.6))
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(captureMode == mode ? Color.black.opacity(0.6) : Color.clear)
                .cornerRadius(segmentCornerRadius)
        }
        .buttonStyle(.plain)
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

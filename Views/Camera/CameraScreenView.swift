import SwiftUI

// 相机主界面容器
struct CameraScreenView: View {
    // 本地媒体库（用于缩略图与图库）
    @StateObject private var library: LocalMediaLibrary = LocalMediaLibrary.shared
    // 相机会话控制器共享到取景与快门
    @StateObject private var cameraController: CameraSessionController
    @State private var selectedTemplate: String? = nil
    @EnvironmentObject private var debugSettings: DebugSettings

    init() {
        _cameraController = StateObject(wrappedValue: CameraSessionController(library: LocalMediaLibrary.shared))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let screenHeight = proxy.size.height
                // 顶部高度按屏幕比例计算，并限制最小/最大值，保证不同机型一致观感
                let topHeight = clamp(screenHeight * 0.07, min: 48, max: 72)
                // 先为 4:3 取景框 + 顶部间距让路，空间不足时优先压缩底栏
                let desiredTopGap: CGFloat = 14
                let viewfinderHeight = proxy.size.width * 4.0 / 3.0
                let minBottomHeight: CGFloat = 160
                let preferredBottomHeight = clamp(screenHeight * 0.24, min: 200, max: 300)
                let spaceAfterTopAndViewfinder = screenHeight - topHeight - viewfinderHeight
                let maxBottomToKeepTopGap = spaceAfterTopAndViewfinder - desiredTopGap
                let bottomHeight = clamp(
                    preferredBottomHeight,
                    min: minBottomHeight,
                    max: max(minBottomHeight, maxBottomToKeepTopGap)
                )

                // 顶部 / 取景 / 底部 三段结构
                VStack(spacing: 0) {
                    TopBarView(
                        height: topHeight,
                        cameraController: cameraController,
                        onSelectTemplate: { selectedTemplate = $0 }
                    )
                    ViewfinderView(
                        cameraController: cameraController,
                        selectedTemplate: selectedTemplate,
                        guidanceUIMode: debugSettings.guidanceUIMode,
                        showDebugHUD: debugSettings.showDebugHUD
                    )
                    BottomBarView(
                        height: bottomHeight,
                        cameraController: cameraController,
                        latestThumbnail: library.latestThumbnail,
                        selectedTemplate: $selectedTemplate
                    )
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .onChange(of: selectedTemplate) { newValue in
                    cameraController.setSelectedTemplate(newValue)
                }
            }
            // 使用安全区，但不额外忽略，避免内容进入刘海/下巴区域
            .ignoresSafeArea(.container, edges: [])
        }
        .environmentObject(library)
    }

    // 数值夹取，避免布局失控
    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(value, max))
    }
}

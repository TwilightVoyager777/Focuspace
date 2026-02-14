import SwiftUI

// 相机主界面容器
struct CameraScreenView: View {
    // 本地媒体库（用于缩略图与图库）
    @StateObject private var library: LocalMediaLibrary = LocalMediaLibrary.shared
    // 相机会话控制器共享到取景与快门
    @StateObject private var cameraController: CameraSessionController

    init() {
        _cameraController = StateObject(wrappedValue: CameraSessionController(library: LocalMediaLibrary.shared))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let screenHeight = proxy.size.height
                // 顶部高度按屏幕比例计算，并限制最小/最大值，保证不同机型一致观感
                let topHeight = clamp(screenHeight * 0.07, min: 48, max: 72)
                // 底部高度按屏幕比例计算，并限制最小/最大值
                let bottomHeight = clamp(screenHeight * 0.18, min: 180, max: 280)

                // 顶部 / 取景 / 底部 三段结构
                VStack(spacing: 0) {
                    TopBarView(height: topHeight, cameraController: cameraController)
                    ViewfinderView(cameraController: cameraController)
                    BottomBarView(
                        height: bottomHeight,
                        cameraController: cameraController,
                        latestThumbnail: library.latestThumbnail
                    )
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
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

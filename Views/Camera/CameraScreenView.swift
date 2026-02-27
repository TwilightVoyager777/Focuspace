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
                let screenWidth = proxy.size.width
                let screenHeight = proxy.size.height
                let isPadLikeWidth = screenWidth >= 700
                let usePadPortraitLayout = isPadLikeWidth && screenHeight > screenWidth
                Group {
                    if usePadPortraitLayout {
                        // iPad portrait: full-screen viewfinder with overlay controls, close to native Camera layout.
                        let topHeight = clamp(screenHeight * 0.078, min: 74, max: 96)
                        let bottomHeight = clamp(screenHeight * 0.225, min: 178, max: 250)

                        ZStack {
                            ViewfinderView(
                                cameraController: cameraController,
                                selectedTemplate: selectedTemplate,
                                usePadPortraitLayout: true,
                                guidanceUIMode: debugSettings.guidanceUIMode,
                                showGuidanceDebugHUD: debugSettings.showGuidanceDebugHUD,
                                showAICoachDebugHUD: debugSettings.showAICoachDebugHUD
                            )
                            .frame(width: proxy.size.width, height: proxy.size.height)

                            VStack(spacing: 0) {
                                TopBarView(
                                    height: topHeight,
                                    cameraController: cameraController,
                                    usePadPortraitLayout: true,
                                    onSelectTemplate: { selectedTemplate = $0 }
                                )
                                Spacer(minLength: 0)
                                BottomBarView(
                                    height: bottomHeight,
                                    cameraController: cameraController,
                                    latestThumbnail: library.latestThumbnail,
                                    usePadPortraitLayout: true,
                                    selectedTemplate: $selectedTemplate
                                )
                            }
                            .padding(.top, proxy.safeAreaInsets.top)
                            .padding(.bottom, max(proxy.safeAreaInsets.bottom, 8))
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    } else {
                        // iPhone path: keep the original 3-section layout unchanged.
                        let topHeight = clamp(screenHeight * 0.07, min: 48, max: 72)
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

                        VStack(spacing: 0) {
                            TopBarView(
                                height: topHeight,
                                cameraController: cameraController,
                                usePadPortraitLayout: false,
                                onSelectTemplate: { selectedTemplate = $0 }
                            )
                            ViewfinderView(
                                cameraController: cameraController,
                                selectedTemplate: selectedTemplate,
                                usePadPortraitLayout: false,
                                guidanceUIMode: debugSettings.guidanceUIMode,
                                showGuidanceDebugHUD: debugSettings.showGuidanceDebugHUD,
                                showAICoachDebugHUD: debugSettings.showAICoachDebugHUD
                            )
                            BottomBarView(
                                height: bottomHeight,
                                cameraController: cameraController,
                                latestThumbnail: library.latestThumbnail,
                                usePadPortraitLayout: false,
                                selectedTemplate: $selectedTemplate
                            )
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .onChange(of: selectedTemplate) { _, newValue in
                    if let newValue, !cameraController.isTemplateSupported(newValue) {
                        cameraController.notifyUnsupportedTemplateSelection(newValue)
                        selectedTemplate = cameraController.selectedTemplateID
                        return
                    }
                    let canonical = TemplateType.canonicalID(for: newValue)
                    if canonical != newValue {
                        selectedTemplate = canonical
                    }
                    cameraController.setSelectedTemplate(canonical)
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

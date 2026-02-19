import SwiftUI

// 底部控制区域
enum BottomPanel {
    case tools
    case templates
}

struct BottomBarView: View {
    let height: CGFloat
    let cameraController: CameraSessionController
    let latestThumbnail: UIImage?
    @Binding var selectedTemplate: String?

    @State private var bottomPanel: BottomPanel = .tools
    @State private var selectedTemplateID: String = "symmetry"
    @State private var isToolAdjusting: Bool = false

    private let compositionOverlay = CompositionOverlayController()
    private let topRowHeight: CGFloat = 110

    private var panelOffset: CGFloat {
        bottomPanel == .templates || isToolAdjusting ? 20 : 0
    }

    private var bottomControlsOffset: CGFloat {
        -35 + (bottomPanel == .templates ? 12 : 0)
    }

    private var slideAnimation: Animation {
        .easeInOut(duration: 0.35)
    }

    var body: some View {
        VStack(spacing: 18) {
            // 工具条（可横向滚动）
            ZStack {
                if bottomPanel == .tools {
                    BottomC1ToolsRowView(
                        cameraController: cameraController,
                        isAdjusting: $isToolAdjusting
                    )
                } else {
                    TemplateRowView(
                        selectedTemplateID: $selectedTemplateID,
                        onSelect: { template in
                            selectedTemplateID = template.id
                            selectedTemplate = template.id
                            compositionOverlay.setTemplate(template.id)
                        }
                    )
                    .frame(height: topRowHeight)
                    .clipped()
                }
            }
            .onChange(of: bottomPanel) { newValue in
                if newValue == .templates {
                    isToolAdjusting = false
                }
            }
            .frame(height: topRowHeight)
            .offset(y: panelOffset - 7)
            .animation(slideAnimation, value: bottomPanel)

            // 下方控制行：缩略图 + 快门 + 切换镜头
            BottomControlsView(
                cameraController: cameraController,
                latestThumbnail: latestThumbnail,
                onToggleBottomPanel: {
                    withAnimation(slideAnimation) {
                        bottomPanel = bottomPanel == .templates ? .tools : .templates
                    }
                }
            )
            .offset(y: panelOffset + bottomControlsOffset)
            .animation(slideAnimation, value: bottomPanel)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color.black)
        .frame(height: height)
        .frame(maxWidth: .infinity)
    }
}

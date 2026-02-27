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
    let usePadPortraitLayout: Bool
    @Binding var selectedTemplate: String?

    @State private var bottomPanel: BottomPanel = .tools
    @State private var selectedTemplateID: String = "symmetry"
    @State private var pickerHighlightedTemplateID: String? = nil
    @State private var isToolAdjusting: Bool = false

    private var verticalPadding: CGFloat {
        clamp(height * (usePadPortraitLayout ? 0.03 : 0.03), min: usePadPortraitLayout ? 4 : 4, max: usePadPortraitLayout ? 8 : 8)
    }

    private var rowSpacing: CGFloat {
        clamp(height * (usePadPortraitLayout ? 0.05 : 0.05), min: usePadPortraitLayout ? 6 : 6, max: usePadPortraitLayout ? 12 : 12)
    }

    private var contentHeight: CGFloat {
        max(0, height - (verticalPadding * 2) - rowSpacing)
    }

    private var controlsHeight: CGFloat {
        clamp(
            contentHeight * (usePadPortraitLayout ? 0.44 : 0.42),
            min: usePadPortraitLayout ? 84 : 86,
            max: usePadPortraitLayout ? 102 : 92
        )
    }

    private var topRowHeight: CGFloat {
        let remaining = contentHeight - controlsHeight
        return clamp(remaining, min: usePadPortraitLayout ? 56 : 52, max: usePadPortraitLayout ? 118 : 110)
    }

    private var slideAnimation: Animation {
        .easeInOut(duration: 0.35)
    }

    private var isToolAdjustingActive: Bool {
        bottomPanel == .tools && isToolAdjusting
    }

    private var toolsRowOffsetY: CGFloat {
        isToolAdjustingActive ? (usePadPortraitLayout ? 9 : 10) : (usePadPortraitLayout ? -4 : -6)
    }

    private var bottomControlsOffsetY: CGFloat {
        if bottomPanel == .templates {
            return usePadPortraitLayout ? 10 : 12
        }
        return isToolAdjustingActive ? (usePadPortraitLayout ? 12 : 14) : (usePadPortraitLayout ? -10 : -14)
    }

    var body: some View {
        let barBackground = usePadPortraitLayout ? Color.clear : Color.black

        VStack(spacing: rowSpacing) {
            // 工具条（可横向滚动）
            ZStack {
                BottomC1ToolsRowView(
                    cameraController: cameraController,
                    isAdjusting: $isToolAdjusting
                )
                .offset(y: toolsRowOffsetY)
                .opacity(bottomPanel == .tools ? 1 : 0)
                .offset(y: bottomPanel == .tools ? 0 : -10)
                .allowsHitTesting(bottomPanel == .tools)

                TemplateRowView(
                    selectedTemplateID: $selectedTemplateID,
                    highlightedTemplateID: pickerHighlightedTemplateID,
                    onSelect: { template in
                        let tappedID = template.id
                        guard cameraController.isTemplateSupported(tappedID) else {
                            cameraController.notifyUnsupportedTemplateSelection(tappedID)
                            return
                        }
                        if selectedTemplate == tappedID {
                            selectedTemplateID = ""
                            selectedTemplate = nil
                            pickerHighlightedTemplateID = nil
                            cameraController.setSelectedTemplate(nil)
                        } else {
                            selectedTemplateID = tappedID
                            selectedTemplate = tappedID
                            pickerHighlightedTemplateID = tappedID
                            cameraController.setSelectedTemplate(tappedID)
                        }
                    }
                )
                .frame(height: topRowHeight)
                .clipped()
                .opacity(bottomPanel == .templates ? 1 : 0)
                .offset(y: bottomPanel == .templates ? 8 : 10)
                .allowsHitTesting(bottomPanel == .templates)
            }
            .onChange(of: bottomPanel) { _, newValue in
                if newValue == .templates {
                    isToolAdjusting = false
                    pickerHighlightedTemplateID = nil
                }
            }
            .frame(height: topRowHeight)
            .animation(slideAnimation, value: bottomPanel)

            // 下方控制行：缩略图 + 快门 + 切换镜头
            BottomControlsView(
                cameraController: cameraController,
                latestThumbnail: latestThumbnail,
                usePadPortraitLayout: usePadPortraitLayout,
                onToggleBottomPanel: {
                    if bottomPanel == .tools {
                        pickerHighlightedTemplateID = nil
                    }
                    withAnimation(slideAnimation) {
                        bottomPanel = bottomPanel == .templates ? .tools : .templates
                    }
                },
                onSmartCompose: {
                    cameraController.triggerSmartComposeRecommendation { recommendedTemplateID in
                        guard let recommendedTemplateID else { return }
                        let canonical = TemplateType.canonicalID(for: recommendedTemplateID) ?? recommendedTemplateID
                        guard cameraController.isTemplateSupported(canonical) else {
                            cameraController.notifyUnsupportedTemplateSelection(canonical)
                            return
                        }
                        selectedTemplateID = canonical
                        selectedTemplate = canonical
                        pickerHighlightedTemplateID = canonical
                        cameraController.setSelectedTemplate(canonical)
                    }
                }
            )
            .frame(height: controlsHeight)
            .offset(y: bottomControlsOffsetY)
            .animation(slideAnimation, value: bottomPanel)
        }
        .padding(.horizontal, usePadPortraitLayout ? 18 : 16)
        .padding(.top, verticalPadding)
        .padding(.bottom, verticalPadding)
        .background(barBackground)
        .frame(height: height)
        .frame(maxWidth: .infinity)
    }

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(value, max))
    }
}

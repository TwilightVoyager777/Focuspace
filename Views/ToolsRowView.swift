import SwiftUI

// 底部工具条（C1）
struct BottomC1ToolsRowView: View {
    let cameraController: CameraSessionController

    // 工具列表
    private let items: [ToolItem] = [
        ToolItem(title: "前置", systemName: "camera.rotate"),
        ToolItem(title: "对焦", systemName: "viewfinder"),
        ToolItem(title: "白平衡", systemName: "circle.lefthalf.filled"),
        ToolItem(title: "感光", systemName: "sun.max"),
        ToolItem(title: "快门速度", systemName: "timer"),
        ToolItem(title: "曝光", systemName: "circle.dashed"),
        ToolItem(title: "设置", systemName: "gearshape")
    ]

    // 默认高亮项
    private let selectedTitle: String = "感光"

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(items) { item in
                    ToolButtonView(
                        title: item.title,
                        systemName: item.systemName,
                        isSelected: isItemSelected(item),
                        action: {
                            handleTap(for: item.title)
                        }
                    )
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func isItemSelected(_ item: ToolItem) -> Bool {
        if item.title == "对焦" {
            return cameraController.isFocusLocked
        }
        return item.title == selectedTitle
    }

    private func handleTap(for title: String) {
        switch title {
        case "前置":
            cameraController.switchCamera()
        case "对焦":
            cameraController.toggleFocusLock()
        default:
            break
        }
    }
}

// 工具数据模型
struct ToolItem: Identifiable {
    let id = UUID()
    let title: String
    let systemName: String
}

// 单个工具按钮
struct ToolButtonView: View {
    let title: String
    let systemName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isSelected ? Color.yellow.opacity(0.9) : Color.white.opacity(0.8))
                    .frame(width: 28, height: 24)

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isSelected ? Color.yellow.opacity(0.9) : Color.white.opacity(0.7))
            }
            .frame(minWidth: 48)
        }
        .buttonStyle(.plain)
    }
}

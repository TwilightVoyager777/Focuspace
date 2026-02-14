import Foundation

// 工具数据模型
struct ToolItem: Identifiable {
    let id: String
    let title: String
    let systemName: String
    let isEnabled: Bool

    init(title: String, systemName: String, isEnabled: Bool = true) {
        self.id = title
        self.title = title
        self.systemName = systemName
        self.isEnabled = isEnabled
    }
}

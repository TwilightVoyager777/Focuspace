import SwiftUI

struct AICoachDebugHUDView: View {
    var smartComposeActive: Bool
    var smartComposeProcessing: Bool
    var score: Int
    var shouldHold: Bool
    var instruction: String
    var reason: String
    var suggestedTemplateID: String?
    var suggestedTemplateReason: String?
    var availabilityMessage: String?

    private func boolText(_ value: Bool) -> String {
        value ? "是" : "否"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AI HUD")
            Text("智能构图激活: \(boolText(smartComposeActive))")
            Text("智能构图处理中: \(boolText(smartComposeProcessing))")
            Text("分数: \(score)")
            Text("建议保持: \(boolText(shouldHold))")
            Text("指令: \(instruction.isEmpty ? "无" : instruction)")
            Text("原因: \(reason.isEmpty ? "无" : reason)")
            Text("建议模板: \(suggestedTemplateID ?? "无")")
            if let suggestedTemplateReason, !suggestedTemplateReason.isEmpty {
                Text("模板理由: \(suggestedTemplateReason)")
            }
            if let availabilityMessage, !availabilityMessage.isEmpty {
                Text("状态: \(availabilityMessage)")
            }
        }
        .font(.system(size: 12, weight: .regular, design: .monospaced))
        .foregroundColor(.white)
        .padding(8)
        .background(.black.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

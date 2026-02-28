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
        value ? "Yes" : "No"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AI HUD")
            Text("Smart Compose Active: \(boolText(smartComposeActive))")
            Text("Smart Compose Processing: \(boolText(smartComposeProcessing))")
            Text("Score: \(score)")
            Text("Should Hold: \(boolText(shouldHold))")
            Text("Instruction: \(instruction.isEmpty ? "None" : instruction)")
            Text("Reason: \(reason.isEmpty ? "None" : reason)")
            Text("Suggested Template: \(suggestedTemplateID ?? "None")")
            if let suggestedTemplateReason, !suggestedTemplateReason.isEmpty {
                Text("Template Reason: \(suggestedTemplateReason)")
            }
            if let availabilityMessage, !availabilityMessage.isEmpty {
                Text("Status: \(availabilityMessage)")
            }
        }
        .font(.system(size: 12, weight: .regular, design: .monospaced))
        .foregroundColor(.white)
        .padding(8)
        .background(.black.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

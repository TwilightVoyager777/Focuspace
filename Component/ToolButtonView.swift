import SwiftUI

// 单个工具按钮
struct ToolButtonView: View {
    let title: String
    let systemName: String
    let isSelected: Bool
    let isEnabled: Bool
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
        .opacity(isEnabled ? 1.0 : 0.35)
        .allowsHitTesting(isEnabled)
    }
}

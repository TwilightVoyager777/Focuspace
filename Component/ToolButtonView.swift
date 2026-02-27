import SwiftUI

// 单个工具按钮
struct ToolButtonView: View {
    let title: String
    let systemName: String
    let isSelected: Bool
    let isEnabled: Bool
    var useLandscapeSidebarLayout: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if useLandscapeSidebarLayout {
                VStack(spacing: 6) {
                    Image(systemName: systemName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isSelected ? Color.yellow.opacity(0.95) : Color.white.opacity(0.82))
                        .frame(width: 48, height: 48)
                        .background(
                            Circle()
                                .fill(Color.gray.opacity(isSelected ? 0.64 : 0.48))
                        )

                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isSelected ? Color.white : Color.white.opacity(0.86))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 72)
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            } else {
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
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1.0 : 0.35)
        .allowsHitTesting(isEnabled)
    }
}

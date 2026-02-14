import SwiftUI

// 右侧智能模版入口按钮
struct TemplateToggleButtonView: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 49, height: 49)
        }
        .buttonStyle(.plain)
    }
}

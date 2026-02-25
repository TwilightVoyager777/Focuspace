import SwiftUI

struct TemplateRowCardView: View {
    let item: TemplateItem
    let isSelected: Bool
    let onSelect: (TemplateItem) -> Void

    var body: some View {
        Button(action: {
            onSelect(item)
        }) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(white: 0.12))

                    CompositionDiagramView(templateID: item.id)
                        .stroke(Color.white.opacity(0.7), lineWidth: 1)
                        .padding(10)
                        .allowsHitTesting(false)
                }
                .frame(width: 60, height: 60)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(isSelected ? Color.orange : Color.white.opacity(0.7), lineWidth: 2)
                )

                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .minimumScaleFactor(0.9)
                    .frame(maxWidth: 68)
            }
        }
        .buttonStyle(.plain)
    }
}

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
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(white: 0.16))
                        .overlay(
                            Image(item.imageName)
                                .resizable()
                                .scaledToFill()
                                .opacity(0.9)
                        )
                        .overlay(Color.black.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.6))
                }
                .frame(width: 76, height: 76)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(isSelected ? Color.orange : Color.white.opacity(0.7), lineWidth: 2)
                )

                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(maxWidth: 76)
            }
        }
        .buttonStyle(.plain)
    }
}

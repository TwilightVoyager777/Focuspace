import SwiftUI

struct TemplateItem: Identifiable {
    let id: String
    let title: String
    let imageName: String
}

struct TemplateRowView: View {
    @Binding var selectedTemplateID: String
    let onSelect: (TemplateItem) -> Void

    private let items: [TemplateItem] = [
        TemplateItem(id: "symmetry", title: "对称", imageName: "template_symmetry"),
        TemplateItem(id: "center", title: "居中", imageName: "template_center"),
        TemplateItem(id: "thirds", title: "三分法", imageName: "template_thirds"),
        TemplateItem(id: "negativeSpace", title: "留白", imageName: "template_negative_space")
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(items) { item in
                    TemplateRowCardView(
                        item: item,
                        isSelected: item.id == selectedTemplateID,
                        onSelect: onSelect
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.black.allowsHitTesting(false))
    }
}

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

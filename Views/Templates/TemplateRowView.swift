import SwiftUI

struct TemplateRowView: View {
    @Binding var selectedTemplateID: String
    let highlightedTemplateID: String?
    let onSelect: (TemplateItem) -> Void

    private let items: [TemplateItem] = [
        TemplateItem(id: "symmetry", title: "对称", imageName: "template_symmetry"),
        TemplateItem(id: "center", title: "居中", imageName: "template_center"),
        TemplateItem(id: "thirds", title: "三分法", imageName: "template_thirds"),
        TemplateItem(id: "goldenPoints", title: "黄金点", imageName: "template_thirds"),
        TemplateItem(id: "diagonal", title: "对角线", imageName: "template_center"),
        TemplateItem(id: "negativeSpaceLeft", title: "留白-左", imageName: "template_negative_space"),
        TemplateItem(id: "negativeSpaceRight", title: "留白-右", imageName: "template_negative_space"),
        TemplateItem(id: "negativeSpaceTop", title: "留白-上", imageName: "template_negative_space"),
        TemplateItem(id: "negativeSpaceBottom", title: "留白-下", imageName: "template_negative_space")
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(items) { item in
                    TemplateRowCardView(
                        item: item,
                        isSelected: item.id == highlightedTemplateID,
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


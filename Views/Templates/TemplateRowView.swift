import SwiftUI

struct TemplateRowView: View {
    @Binding var selectedTemplateID: String
    let highlightedTemplateID: String?
    let onSelect: (TemplateItem) -> Void

    private let items: [TemplateItem] = [
        TemplateItem(id: "symmetry", title: "Symmetry", imageName: "template_symmetry"),
        TemplateItem(id: "center", title: "Center", imageName: "template_center"),
        TemplateItem(id: "thirds", title: "Rule of Thirds", imageName: "template_thirds"),
        TemplateItem(id: "goldenPoints", title: "Golden Points", imageName: "template_thirds"),
        TemplateItem(id: "diagonal", title: "Diagonal", imageName: "template_center"),
        TemplateItem(id: "negativeSpace", title: "Negative Space", imageName: "template_negative_space")
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

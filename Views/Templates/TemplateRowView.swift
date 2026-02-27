import SwiftUI

struct TemplateRowView: View {
    @Binding var selectedTemplateID: String
    let highlightedTemplateID: String?
    var useLandscapeSidebarLayout: Bool = false
    let onSelect: (TemplateItem) -> Void

    private let templates: [CompositionTemplate] = sortTemplates(TemplateCatalog.load())

    private var items: [TemplateItem] {
        templates.map { template in
            let examples = TemplateCatalog.resolvedExamples(
                templateID: template.id,
                explicit: template.examples
            )
            return TemplateItem(
                id: template.id,
                title: shortTitle(for: template.id, fallback: template.name),
                imageName: examples.first ?? "template_center"
            )
        }
    }

    var body: some View {
        Group {
            if useLandscapeSidebarLayout {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        ForEach(items) { item in
                            TemplateRowCardView(
                                item: item,
                                isSelected: item.id == highlightedTemplateID,
                                useLandscapeSidebarLayout: true,
                                onSelect: onSelect
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                }
            } else {
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
            }
        }
        .background((useLandscapeSidebarLayout ? Color.clear : Color.black).allowsHitTesting(false))
    }
}

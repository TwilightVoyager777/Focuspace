import Foundation

func sortTemplates<T: TemplateSortable>(_ templates: [T]) -> [T] {
    templates.sorted { lhs, rhs in
        let leftOrder = TemplateRegistry.sortIndex(for: lhs.id)
        let rightOrder = TemplateRegistry.sortIndex(for: rhs.id)

        if let leftOrder, let rightOrder {
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        if leftOrder != nil {
            return true
        }
        if rightOrder != nil {
            return false
        }

        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

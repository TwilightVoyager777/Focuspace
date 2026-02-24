import Foundation

protocol TemplateSortable {
    var id: String { get }
    var name: String { get }
}

private let templateOrderIndex: [String: Int] = [
    "symmetry": 0,
    "center": 1,
    "leading_lines": 2,
    "golden_spiral": 3,
    "framing": 4,
    "diagonals": 5,
    "negative_space": 6,
    "portrait_headroom": 7,
    "triangle": 8,
    "layers_fmb": 9,
    "rule_of_thirds": 10
]

func sortTemplates<T: TemplateSortable>(_ templates: [T]) -> [T] {
    templates.sorted { lhs, rhs in
        let leftOrder = templateOrderIndex[lhs.id]
        let rightOrder = templateOrderIndex[rhs.id]

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

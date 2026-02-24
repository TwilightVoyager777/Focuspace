import Foundation

func shortTitle(for templateId: String, fallback: String) -> String {
    switch templateId {
    case "symmetry":
        return "Symmetry"
    case "center":
        return "Center"
    case "leading_lines":
        return "Leading Lines"
    case "golden_spiral":
        return "Spiral"
    case "framing":
        return "Framing"
    case "diagonals":
        return "Diagonals"
    case "negative_space":
        return "Negative Space"
    case "portrait_headroom":
        return "Headroom"
    case "triangle":
        return "Triangle"
    case "layers_fmb":
        return "Layers"
    case "rule_of_thirds":
        return "Thirds"
    default:
        return fallback
    }
}

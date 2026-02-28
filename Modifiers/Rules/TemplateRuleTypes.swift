import CoreGraphics

enum CompositionTemplateType {
    case symmetry
    case center
    case leadingLines
    case framing
    case thirds
    case goldenPoints
    case diagonal
    case negativeSpace
    case portraitHeadroom
    case triangle
    case layersFMB
    case other

    init(id: String?) {
        switch id {
        case "symmetry":
            self = .symmetry
        case "center":
            self = .center
        case "leading_lines":
            self = .leadingLines
        case "framing":
            self = .framing
        case "rule_of_thirds", "thirds":
            self = .thirds
        case "golden_spiral", "goldenPoints":
            self = .goldenPoints
        case "diagonals", "diagonal":
            self = .diagonal
        case "negative_space", "negativeSpace":
            self = .negativeSpace
        case "portrait_headroom", "portraitHeadroom":
            self = .portraitHeadroom
        case "triangle":
            self = .triangle
        case "layers_fmb", "layersFMB":
            self = .layersFMB
        default:
            self = .other
        }
    }

    var canonicalTemplateID: String? {
        switch self {
        case .symmetry:
            return "symmetry"
        case .center:
            return "center"
        case .leadingLines:
            return "leading_lines"
        case .framing:
            return "framing"
        case .thirds:
            return "rule_of_thirds"
        case .goldenPoints:
            return "golden_spiral"
        case .diagonal:
            return "diagonals"
        case .negativeSpace:
            return "negative_space"
        case .portraitHeadroom:
            return "portrait_headroom"
        case .triangle:
            return "triangle"
        case .layersFMB:
            return "layers_fmb"
        case .other:
            return nil
        }
    }

    static let supportedTemplateIDs: Set<String> = TemplateRegistry.supportedIDs

    static func canonicalID(for id: String?) -> String? {
        CompositionTemplateType(id: id).canonicalTemplateID
    }

    static func isSupportedTemplateID(_ id: String?) -> Bool {
        guard let canonical = canonicalID(for: id) else { return false }
        return supportedTemplateIDs.contains(canonical)
    }
}

struct TemplateComputationResult {
    var guidance: GuidanceOutput
    var targetPoint: CGPoint?
    var diagonalType: DiagonalType?
    var negativeSpaceZone: CGRect?
}

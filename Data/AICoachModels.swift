struct AICoachFrameSnapshot: Sendable {
    var templateID: String?
    var subjectX: Double?
    var subjectY: Double?
    var targetX: Double?
    var targetY: Double?
    var stableDx: Double
    var stableDy: Double
    var confidence: Double
    var isLost: Bool
    var structuralTags: [String] = []

    var sceneSummary: String {
        let templateLabel = templateID ?? "none"
        if isLost || confidence < 0.25 {
            return "subject unstable template \(templateLabel)"
        }
        let horizontal = abs(stableDx)
        let vertical = abs(stableDy)
        if horizontal > 0.28 && vertical > 0.28 {
            return "dynamic diagonal motion template \(templateLabel)"
        }
        if horizontal > vertical {
            return "horizontal offset template \(templateLabel)"
        }
        if vertical > horizontal {
            return "vertical offset template \(templateLabel)"
        }
        return "balanced frame template \(templateLabel)"
    }

    var semanticSignalSummary: String {
        let templateLabel = templateID ?? "none"
        let subjectPosition: String = {
            guard let x = subjectX, let y = subjectY else { return "subject=nil" }
            let horizontal = x < 0.38 ? "left" : (x > 0.62 ? "right" : "center")
            let vertical = y < 0.38 ? "top" : (y > 0.62 ? "bottom" : "mid")
            return "subject=\(horizontal)-\(vertical)"
        }()
        let targetPosition: String = {
            guard let x = targetX, let y = targetY else { return "target=nil" }
            let horizontal = x < 0.38 ? "left" : (x > 0.62 ? "right" : "center")
            let vertical = y < 0.38 ? "top" : (y > 0.62 ? "bottom" : "mid")
            return "target=\(horizontal)-\(vertical)"
        }()
        let drift: String = {
            let horizontal = stableDx > 0.10 ? "move-right" : (stableDx < -0.10 ? "move-left" : "h-stable")
            let vertical = stableDy > 0.10 ? "move-down" : (stableDy < -0.10 ? "move-up" : "v-stable")
            return "drift=\(horizontal),\(vertical)"
        }()
        let confidenceBand: String = {
            if isLost || confidence < 0.25 { return "low" }
            if confidence < 0.60 { return "mid" }
            return "high"
        }()
        let structural = structuralTags.isEmpty
            ? "structural=none"
            : "structural=\(structuralTags.joined(separator: ","))"
        return "\(subjectPosition) \(targetPosition) \(drift) confidence=\(confidenceBand) template=\(templateLabel) \(structural)"
    }
}

struct AICoachAdvice: Sendable {
    var instruction: String
    var score: Int
    var shouldHold: Bool
    var reason: String
    var suggestedTemplateID: String?
    var suggestedTemplateReason: String?
    var availabilityMessage: String?
    var usedFoundationModel: Bool
}

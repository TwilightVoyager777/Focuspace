import CoreGraphics
import Foundation

enum SmartComposeRecommendationResolver {
    static func resolveTemplateDecision(
        adviceTemplateID: String?,
        adviceReason: String?,
        snapshot: AICoachFrameSnapshot
    ) -> (id: String, reason: String) {
        if let suggested = CompositionTemplateType.canonicalID(for: adviceTemplateID),
           CompositionTemplateType.isSupportedTemplateID(suggested),
           suggested != "center" {
            return (suggested, adviceReason ?? "AI selected this template.")
        }

        if let current = CompositionTemplateType.canonicalID(for: snapshot.templateID),
           CompositionTemplateType.isSupportedTemplateID(current),
           current != "center" {
            return (current, "Keep the active template for continuity.")
        }

        if let heuristic = heuristicTemplate(snapshot: snapshot) {
            return heuristic
        }

        return ("rule_of_thirds", "Fallback to thirds to avoid center lock.")
    }

    static func recommendedZoom(
        templateID: String,
        score: Int,
        currentZoom: CGFloat,
        minimumZoomIncrease: CGFloat
    ) -> CGFloat {
        let base: CGFloat
        switch templateID {
        case "portrait_headroom":
            base = 1.58
        case "rule_of_thirds", "golden_spiral":
            base = 1.36
        case "center", "symmetry":
            base = 1.28
        case "triangle", "layers_fmb":
            base = 1.30
        case "leading_lines":
            base = 1.18
        case "negative_space", "framing":
            base = 1.14
        default:
            base = 1.26
        }

        let scoreRatio = max(0, min(1, CGFloat(score) / 100))
        let adaptive = base - (1 - scoreRatio) * 0.14
        let ensuredIncrease = max(adaptive, currentZoom + minimumZoomIncrease)
        return max(0.7, min(8.0, ensuredIncrease))
    }

    private static func heuristicTemplate(
        snapshot: AICoachFrameSnapshot
    ) -> (id: String, reason: String)? {
        let confidence = CGFloat(max(0, min(1, snapshot.confidence)))
        let subject: CGPoint? = {
            guard let x = snapshot.subjectX, let y = snapshot.subjectY else { return nil }
            return CGPoint(
                x: CGFloat(max(0, min(1, x))),
                y: CGFloat(max(0, min(1, y)))
            )
        }()

        if snapshot.isLost || confidence < 0.18 {
            return ("rule_of_thirds", "Tracking weak. Use thirds to recover subject lock.")
        }

        guard let subject else {
            return ("rule_of_thirds", "No subject point yet. Start with thirds.")
        }

        let dx = subject.x - 0.5
        let dy = subject.y - 0.5
        let absX = abs(dx)
        let absY = abs(dy)

        if absX > 0.24, absX > absY + 0.06 {
            return ("negative_space", "Strong horizontal offset. Leave intentional negative space.")
        }
        if absY > 0.24, absY > absX + 0.06 {
            return ("portrait_headroom", "Strong vertical offset. Balance with portrait headroom.")
        }
        if absX > 0.16, absY > 0.16 {
            return ("diagonals", "Dual-axis offset fits diagonal composition.")
        }
        if absX > 0.09 || absY > 0.09 {
            return ("rule_of_thirds", "Offset subject fits thirds better than center.")
        }
        return ("rule_of_thirds", "Balanced scene. Use thirds for intentional framing.")
    }
}

import Foundation

enum AICoachDeterministicEngine {
    struct TemplatePick {
        let templateID: String
        let reason: String
    }

    struct AlignmentScore {
        let score: Int
        let instruction: String
        let shouldHold: Bool
        let reason: String
    }

    static func pickTemplate(from scene: String) -> TemplatePick {
        let lower = scene.lowercased()
        if lower.contains("unstable") || lower.contains("none") {
            return TemplatePick(
                templateID: "center",
                reason: "Use center until tracking is stable."
            )
        }
        if lower.contains("diagonal") || lower.contains("dynamic") {
            return TemplatePick(
                templateID: "leading_lines",
                reason: "Directional energy fits leading lines better now."
            )
        }
        if lower.contains("horizontal") {
            return TemplatePick(
                templateID: "rule_of_thirds",
                reason: "Thirds gives room for horizontal correction."
            )
        }
        if lower.contains("vertical") {
            return TemplatePick(
                templateID: "portrait_headroom",
                reason: "Portrait headroom stabilizes vertical framing."
            )
        }
        return TemplatePick(
            templateID: "symmetry",
            reason: "Symmetry works when the frame is already balanced."
        )
    }

    static func pickTemplate(from snapshot: AICoachFrameSnapshot) -> TemplatePick {
        let scores = templateScores(for: snapshot).filter {
            CompositionTemplateType.isSupportedTemplateID($0.key)
        }
        guard let best = scores.max(by: { $0.value < $1.value }) else {
            return pickTemplate(from: snapshot.sceneSummary)
        }
        return TemplatePick(
            templateID: best.key,
            reason: reasonForTemplate(
                best.key,
                snapshot: snapshot,
                fallback: pickTemplate(from: snapshot.sceneSummary).reason
            )
        )
    }

    static func voteScore(for templateID: String, snapshot: AICoachFrameSnapshot) -> Double {
        templateScores(for: snapshot)[templateID] ?? 0
    }

    static func validatedTemplatePick(
        fmTemplateID: String?,
        sceneCategory: String,
        confidenceBand: String,
        snapshot: AICoachFrameSnapshot,
        fallback: TemplatePick
    ) -> TemplatePick {
        guard let fmTemplateID,
              CompositionTemplateType.isSupportedTemplateID(fmTemplateID),
              fmTemplateID != "center" else {
            return fallback
        }

        let fallbackScore = voteScore(for: fallback.templateID, snapshot: snapshot)
        let fmScore = voteScore(for: fmTemplateID, snapshot: snapshot)
        let band = confidenceBand.lowercased()
        let requiredScore: Double = {
            switch band {
            case "high":
                return max(0.28, fallbackScore - 0.28)
            case "mid":
                return max(0.40, fallbackScore - 0.12)
            default:
                return fallbackScore
            }
        }()

        guard fmScore >= requiredScore else {
            return fallback
        }

        return TemplatePick(
            templateID: fmTemplateID,
            reason: reasonForTemplate(
                fmTemplateID,
                snapshot: snapshot,
                fallback: semanticFallbackReason(
                    sceneCategory: sceneCategory,
                    templateID: fmTemplateID,
                    fallback: fallback.reason
                )
            )
        )
    }

    static func scoreAlignment(
        template: String,
        dx: Double,
        dy: Double,
        confidence: Double,
        isLost: Bool
    ) -> AlignmentScore {
        if isLost {
            return AlignmentScore(
                score: 0,
                instruction: "Reacquire subject first.",
                shouldHold: false,
                reason: "Tracking lost."
            )
        }

        let clampedConfidence = clamp(confidence, min: 0, max: 1)
        let distance = sqrt(dx * dx + dy * dy)
        let normalizedDistance = clamp(distance / 0.65, min: 0, max: 1)
        let base = (1 - normalizedDistance) * 100
        let weighted = Int((base * (0.55 + clampedConfidence * 0.45)).rounded())
        let score = clamp(weighted, min: 0, max: 100)
        let shouldHold = score >= 88 && distance <= 0.08 && clampedConfidence >= 0.65

        if shouldHold {
            return AlignmentScore(
                score: score,
                instruction: "Hold steady and shoot.",
                shouldHold: true,
                reason: "Alignment is locked."
            )
        }

        if clampedConfidence < 0.35 {
            return AlignmentScore(
                score: score,
                instruction: "Stabilize tracking first.",
                shouldHold: false,
                reason: "Low confidence."
            )
        }

        let horizontal = abs(dx)
        let vertical = abs(dy)
        let instruction: String
        if horizontal >= vertical {
            instruction = dx > 0 ? "Pan right slightly." : "Pan left slightly."
        } else {
            instruction = dy > 0 ? "Tilt down slightly." : "Tilt up slightly."
        }

        let reason = "\(template) offset \(String(format: "%.2f", distance))."
        return AlignmentScore(score: score, instruction: instruction, shouldHold: false, reason: reason)
    }

    static func parsePickOutput(_ text: String) -> TemplatePick? {
        var templateID: String?
        var reason: String?
        let components = text.split(separator: ";")
        for raw in components {
            let pair = raw.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            let key = pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if key == "templateid" {
                templateID = value
            } else if key == "reason" {
                reason = value
            }
        }
        guard let templateID, !templateID.isEmpty else { return nil }
        return TemplatePick(templateID: templateID, reason: reason ?? "No reason.")
    }

    static func parseScoreOutput(_ text: String) -> AlignmentScore? {
        var scoreValue: Int?
        var instruction: String?
        var shouldHold: Bool?
        var reason: String?
        let components = text.split(separator: ";")
        for raw in components {
            let pair = raw.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            let key = pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
            switch key {
            case "score":
                scoreValue = Int(value)
            case "instruction":
                instruction = value
            case "shouldhold":
                shouldHold = (value as NSString).boolValue
            case "reason":
                reason = value
            default:
                continue
            }
        }
        guard let scoreValue, let instruction else { return nil }
        return AlignmentScore(
            score: clamp(scoreValue, min: 0, max: 100),
            instruction: instruction,
            shouldHold: shouldHold ?? false,
            reason: reason ?? "No reason."
        )
    }

    static func shortInstruction(from text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return String(trimmed.prefix(48))
    }

    static func shortReason(from text: String, fallback: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return String(trimmed.prefix(72))
    }

    static func clamp<T: Comparable>(_ value: T, min lower: T, max upper: T) -> T {
        Swift.max(lower, Swift.min(value, upper))
    }

    private static func templateScores(for snapshot: AICoachFrameSnapshot) -> [String: Double] {
        var scores: [String: Double] = [
            "center": 0.12,
            "symmetry": 0.12,
            "leading_lines": 0.12,
            "framing": 0.12,
            "rule_of_thirds": 0.12,
            "golden_spiral": 0.12,
            "diagonals": 0.12,
            "negative_space": 0.12,
            "portrait_headroom": 0.12,
            "triangle": 0.12,
            "layers_fmb": 0.12
        ]

        func add(_ templateID: String, _ delta: Double) {
            scores[templateID, default: 0] += delta
        }

        let scene = snapshot.sceneSummary.lowercased()
        if scene.contains("unstable") || scene.contains("none") {
            add("center", 0.90)
            add("rule_of_thirds", 0.25)
        } else if scene.contains("diagonal") || scene.contains("dynamic") {
            add("diagonals", 0.72)
            add("golden_spiral", 0.24)
        } else if scene.contains("horizontal") {
            add("rule_of_thirds", 0.46)
            add("leading_lines", 0.24)
            add("negative_space", 0.20)
        } else if scene.contains("vertical") {
            add("portrait_headroom", 0.48)
            add("framing", 0.18)
        } else {
            add("symmetry", 0.32)
            add("framing", 0.18)
        }

        for tag in snapshot.structuralTags {
            switch tag {
            case "tracking-weak":
                add("center", 0.42)
                add("rule_of_thirds", 0.18)
            case "tracking-settling":
                add("framing", 0.12)
                add("rule_of_thirds", 0.10)
            case "tracking-locked":
                add("symmetry", 0.08)
                add("framing", 0.08)
            case "drift-horizontal":
                add("rule_of_thirds", 0.18)
                add("leading_lines", 0.18)
                add("negative_space", 0.12)
            case "drift-vertical":
                add("portrait_headroom", 0.20)
                add("framing", 0.12)
            case "drift-diagonal":
                add("diagonals", 0.22)
                add("golden_spiral", 0.12)
            case "drift-balanced":
                add("symmetry", 0.14)
            case "symmetry-axis-lock", "symmetry-axis-left", "symmetry-axis-right":
                add("symmetry", 0.82)
            case "vanish-left", "vanish-right", "vanish-center", "vanish-high", "vanish-mid":
                add("leading_lines", 0.42)
            case "thirds-intersection":
                add("rule_of_thirds", 0.78)
            case "thirds-vertical-line", "thirds-horizontal-line":
                add("rule_of_thirds", 0.58)
            case "spiral-left", "spiral-right", "spiral-top", "spiral-bottom":
                add("golden_spiral", 0.40)
            case "diagonal-main", "diagonal-anti":
                add("diagonals", 0.86)
            case "diagonal-ambiguous":
                add("diagonals", 0.16)
            case "space-horizontal", "space-vertical", "space-left", "space-right", "space-top", "space-bottom", "space-mid", "space-center":
                add("negative_space", 0.34)
            case "frame-comfort", "frame-recover":
                add("framing", 0.58)
            case "headroom-upper-band", "headroom-mid-band", "headroom-centered", "headroom-side-balanced":
                add("portrait_headroom", 0.42)
            case "triangle-apex", "triangle-base", "triangle-left-edge", "triangle-right-edge":
                add("triangle", 0.46)
            case "depth-mid-band", "depth-center-lane", "depth-left-lane", "depth-right-lane":
                add("layers_fmb", 0.44)
            case "target-shift-left", "target-shift-right":
                add("negative_space", 0.16)
                add("rule_of_thirds", 0.14)
                add("leading_lines", 0.08)
            case "target-shift-up", "target-shift-down":
                add("portrait_headroom", 0.16)
                add("framing", 0.12)
            case "target-shift-diagonal":
                add("diagonals", 0.14)
                add("golden_spiral", 0.10)
            case "target-near-lock":
                add("symmetry", 0.10)
                add("framing", 0.08)
            default:
                continue
            }
        }

        if let current = snapshot.templateID, scores[current] != nil {
            add(current, 0.06)
        }

        return scores
    }

    private static func reasonForTemplate(
        _ templateID: String,
        snapshot: AICoachFrameSnapshot,
        fallback: String
    ) -> String {
        let tags = Set(snapshot.structuralTags)
        switch templateID {
        case "symmetry" where tags.contains("symmetry-axis-lock"):
            return "Algorithm sees a stable visual axis."
        case "leading_lines" where tags.contains("vanish-left") || tags.contains("vanish-right") || tags.contains("vanish-center"):
            return "Algorithm sees a converging line path."
        case "rule_of_thirds" where tags.contains("thirds-intersection"):
            return "Algorithm sees a strong thirds intersection."
        case "golden_spiral" where tags.contains("spiral-left") || tags.contains("spiral-right"):
            return "Algorithm sees spiral-style directional flow."
        case "diagonals" where tags.contains("diagonal-main") || tags.contains("diagonal-anti"):
            return "Algorithm sees diagonal structural energy."
        case "negative_space" where tags.contains("space-horizontal") || tags.contains("space-vertical"):
            return "Algorithm sees usable negative space."
        case "framing" where tags.contains("frame-comfort") || tags.contains("frame-recover"):
            return "Algorithm sees a recoverable framing window."
        case "portrait_headroom" where tags.contains("headroom-upper-band") || tags.contains("headroom-mid-band"):
            return "Algorithm sees portrait-style headroom."
        case "triangle" where tags.contains("triangle-apex") || tags.contains("triangle-base"):
            return "Algorithm sees a stable triangular structure."
        case "layers_fmb" where tags.contains("depth-mid-band"):
            return "Algorithm sees a stable mid-depth layer."
        default:
            return fallback
        }
    }

    private static func semanticFallbackReason(
        sceneCategory: String,
        templateID: String,
        fallback: String
    ) -> String {
        let category = sceneCategory.lowercased()
        if category.contains("portrait") {
            return templateID == "portrait_headroom"
                ? "FM tagged this as a portrait-driven frame."
                : "FM saw portrait structure and shifted composition."
        }
        if category.contains("symmetry") || category.contains("architecture") {
            return templateID == "symmetry"
                ? "FM detected a strong visual axis."
                : "FM detected structured geometry."
        }
        if category.contains("line") || category.contains("road") || category.contains("corridor") {
            return templateID == "leading_lines"
                ? "FM detected directional scene flow."
                : "FM detected strong directional structure."
        }
        if category.contains("minimal") || category.contains("space") {
            return templateID == "negative_space"
                ? "FM detected usable empty space."
                : "FM detected a sparse frame."
        }
        if category.contains("dynamic") || category.contains("action") || category.contains("diagonal") {
            return templateID == "diagonals"
                ? "FM detected dynamic diagonal energy."
                : "FM detected dynamic visual tension."
        }
        return fallback
    }
}

import Foundation

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

private enum DeterministicCoach {
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
                templateID: "diagonals",
                reason: "Diagonal composition matches strong directional energy."
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
}

actor AICoachCoordinator {
    #if canImport(FoundationModels)
    private var foundationRuntime: Any?

    @available(iOS 26.0, *)
    private var runtime: FoundationModelCoachRuntime? {
        get { foundationRuntime as? FoundationModelCoachRuntime }
        set { foundationRuntime = newValue }
    }
    #endif

    func evaluate(snapshot: AICoachFrameSnapshot) async -> AICoachAdvice {
        let pick = DeterministicCoach.pickTemplate(from: snapshot.sceneSummary)
        let templateForScore = snapshot.templateID ?? pick.templateID
        let baseline = DeterministicCoach.scoreAlignment(
            template: templateForScore,
            dx: snapshot.stableDx,
            dy: snapshot.stableDy,
            confidence: snapshot.confidence,
            isLost: snapshot.isLost
        )

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await evaluateWithFoundationModels(snapshot: snapshot, pick: pick, baseline: baseline)
        }
        #endif

        return AICoachAdvice(
            instruction: baseline.instruction,
            score: baseline.score,
            shouldHold: baseline.shouldHold,
            reason: baseline.reason,
            suggestedTemplateID: pick.templateID,
            suggestedTemplateReason: pick.reason,
            availabilityMessage: "Apple Intelligence unavailable. Using algorithm HUD only.",
            usedFoundationModel: false
        )
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func evaluateWithFoundationModels(
        snapshot: AICoachFrameSnapshot,
        pick: DeterministicCoach.TemplatePick,
        baseline: DeterministicCoach.AlignmentScore
    ) async -> AICoachAdvice {
        if runtime == nil {
            runtime = FoundationModelCoachRuntime()
        }
        guard let runtime else {
            return AICoachAdvice(
                instruction: baseline.instruction,
                score: baseline.score,
                shouldHold: baseline.shouldHold,
                reason: baseline.reason,
                suggestedTemplateID: pick.templateID,
                suggestedTemplateReason: pick.reason,
                availabilityMessage: "Apple Intelligence unavailable. Using algorithm HUD only.",
                usedFoundationModel: false
            )
        }

        do {
            return try await runtime.evaluate(
                snapshot: snapshot,
                fallbackPick: pick,
                fallbackScore: baseline
            )
        } catch {
            return AICoachAdvice(
                instruction: baseline.instruction,
                score: baseline.score,
                shouldHold: baseline.shouldHold,
                reason: baseline.reason,
                suggestedTemplateID: pick.templateID,
                suggestedTemplateReason: pick.reason,
                availabilityMessage: "Apple Intelligence temporarily failed. Using algorithm HUD only.",
                usedFoundationModel: false
            )
        }
    }
    #endif
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
@Generable
private struct AICoachModelOutput {
    let instruction: String
    let score: Int
    let shouldHold: Bool
    let reason: String
}

@available(iOS 26.0, *)
private struct PickTemplateTool: Tool {
    @Generable
    struct Arguments {
        let scene: String
    }

    let name = "pick_template"
    let description = "Return deterministic templateID and reason."

    func call(arguments: Arguments) async throws -> String {
        let result = DeterministicCoach.pickTemplate(from: arguments.scene)
        return "templateID=\(result.templateID);reason=\(result.reason)"
    }
}

@available(iOS 26.0, *)
private struct ScoreAlignmentTool: Tool {
    @Generable
    struct Arguments {
        let template: String
        let dx: Double
        let dy: Double
        let confidence: Double
        let isLost: Bool
    }

    let name = "score_alignment"
    let description = "Return deterministic score and short instruction."

    func call(arguments: Arguments) async throws -> String {
        let result = DeterministicCoach.scoreAlignment(
            template: arguments.template,
            dx: arguments.dx,
            dy: arguments.dy,
            confidence: arguments.confidence,
            isLost: arguments.isLost
        )
        return "score=\(result.score);instruction=\(result.instruction);shouldHold=\(result.shouldHold);reason=\(result.reason)"
    }
}

@available(iOS 26.0, *)
private actor FoundationModelCoachRuntime {
    private let pickTool = PickTemplateTool()
    private let scoreTool = ScoreAlignmentTool()
    private let session: LanguageModelSession

    init() {
        let model = SystemLanguageModel.default
        let instructions = """
        Coach composition.
        Be direct.
        Issue imperative guidance only.
        Keep instruction short.
        Keep reason short.
        """
        let tools: [any Tool] = [pickTool, scoreTool]
        session = LanguageModelSession(
            model: model,
            tools: tools,
            instructions: instructions
        )
    }

    func evaluate(
        snapshot: AICoachFrameSnapshot,
        fallbackPick: DeterministicCoach.TemplatePick,
        fallbackScore: DeterministicCoach.AlignmentScore
    ) async throws -> AICoachAdvice {
        let pickText = try await pickTool.call(arguments: .init(scene: snapshot.sceneSummary))
        let parsedPick = DeterministicCoach.parsePickOutput(pickText) ?? fallbackPick

        let activeTemplate = snapshot.templateID ?? parsedPick.templateID
        let scoreText = try await scoreTool.call(arguments: .init(
            template: activeTemplate,
            dx: snapshot.stableDx,
            dy: snapshot.stableDy,
            confidence: snapshot.confidence,
            isLost: snapshot.isLost
        ))
        let parsedScore = DeterministicCoach.parseScoreOutput(scoreText) ?? fallbackScore

        let transcript: Transcript = session.transcript
        let transcriptTail = String(String(describing: transcript).suffix(120))
        let prompt = Prompt("""
        Coach now.
        Use tools.
        Return fields only.
        template=\(snapshot.templateID ?? "none")
        subject=(\(snapshot.subjectX?.description ?? "nil"),\(snapshot.subjectY?.description ?? "nil"))
        target=(\(snapshot.targetX?.description ?? "nil"),\(snapshot.targetY?.description ?? "nil"))
        dx=\(snapshot.stableDx)
        dy=\(snapshot.stableDy)
        confidence=\(snapshot.confidence)
        isLost=\(snapshot.isLost)
        pick=\(pickText)
        score=\(scoreText)
        transcript=\(transcriptTail)
        """)
        let options = GenerationOptions(temperature: 0.0)
        let response = try await session.respond(
            to: prompt,
            generating: AICoachModelOutput.self,
            options: options
        )

        let generated = Self.extractGeneratedOutput(from: response) ?? AICoachModelOutput(
            instruction: parsedScore.instruction,
            score: parsedScore.score,
            shouldHold: parsedScore.shouldHold,
            reason: parsedScore.reason
        )

        return AICoachAdvice(
            instruction: DeterministicCoach.shortInstruction(from: generated.instruction, fallback: parsedScore.instruction),
            score: DeterministicCoach.clamp(generated.score, min: 0, max: 100),
            shouldHold: generated.shouldHold,
            reason: DeterministicCoach.shortReason(from: generated.reason, fallback: parsedScore.reason),
            suggestedTemplateID: parsedPick.templateID,
            suggestedTemplateReason: parsedPick.reason,
            availabilityMessage: nil,
            usedFoundationModel: true
        )
    }

    private static func extractGeneratedOutput(from response: Any) -> AICoachModelOutput? {
        if let direct = response as? AICoachModelOutput {
            return direct
        }
        let mirror = Mirror(reflecting: response)
        for child in mirror.children {
            if child.label == "content", let content = child.value as? AICoachModelOutput {
                return content
            }
        }
        return nil
    }
}
#endif

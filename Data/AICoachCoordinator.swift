import Foundation

actor AICoachCoordinator {
    private let recommendationCooldown: TimeInterval = 1.5
    private var lastRecommendedTemplateID: String?
    private var lastRecommendedReason: String?
    private var lastRecommendationDate: Date?

    #if canImport(FoundationModels)
    private var foundationRuntime: Any?

    @available(iOS 26.0, *)
    private var runtime: FoundationModelCoachRuntime? {
        get { foundationRuntime as? FoundationModelCoachRuntime }
        set { foundationRuntime = newValue }
    }
    #endif

    func evaluate(snapshot: AICoachFrameSnapshot) async -> AICoachAdvice {
        let pick = AICoachDeterministicEngine.pickTemplate(from: snapshot)
        let templateForScore = snapshot.templateID ?? pick.templateID
        let baseline = AICoachDeterministicEngine.scoreAlignment(
            template: templateForScore,
            dx: snapshot.stableDx,
            dy: snapshot.stableDy,
            confidence: snapshot.confidence,
            isLost: snapshot.isLost
        )

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let advice = await evaluateWithFoundationModels(snapshot: snapshot, pick: pick, baseline: baseline)
            return stabilizedAdvice(advice)
        }
        #endif

        let advice = AICoachAdvice(
            instruction: baseline.instruction,
            score: baseline.score,
            shouldHold: baseline.shouldHold,
            reason: baseline.reason,
            suggestedTemplateID: pick.templateID,
            suggestedTemplateReason: pick.reason,
            availabilityMessage: "Apple Intelligence unavailable. Using algorithm HUD only.",
            usedFoundationModel: false
        )
        return stabilizedAdvice(advice)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func evaluateWithFoundationModels(
        snapshot: AICoachFrameSnapshot,
        pick: AICoachDeterministicEngine.TemplatePick,
        baseline: AICoachDeterministicEngine.AlignmentScore
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

    private func stabilizedAdvice(_ advice: AICoachAdvice) -> AICoachAdvice {
        guard let suggestedTemplateID = advice.suggestedTemplateID else {
            return advice
        }

        let now = Date()
        defer {
            lastRecommendedTemplateID = suggestedTemplateID
            lastRecommendedReason = advice.suggestedTemplateReason
            lastRecommendationDate = now
        }

        guard let lastRecommendedTemplateID,
              let lastRecommendationDate,
              now.timeIntervalSince(lastRecommendationDate) < recommendationCooldown,
              lastRecommendedTemplateID != suggestedTemplateID else {
            return advice
        }

        return AICoachAdvice(
            instruction: advice.instruction,
            score: advice.score,
            shouldHold: advice.shouldHold,
            reason: advice.reason,
            suggestedTemplateID: lastRecommendedTemplateID,
            suggestedTemplateReason: lastRecommendedReason ?? "Holding the recent template briefly for stability.",
            availabilityMessage: advice.availabilityMessage,
            usedFoundationModel: advice.usedFoundationModel
        )
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
@Generable
private struct AICoachSemanticOutput {
    let sceneCategory: String
    let recommendedTemplateID: String
    let confidenceBand: String
}

@available(iOS 26.0, *)
private actor FoundationModelCoachRuntime {
    private let session: LanguageModelSession

    init() {
        let model = SystemLanguageModel.default
        let instructions = """
        Analyze scene semantics for camera composition.
        Choose only one template from the allowed template list.
        Do not generate user-facing coaching copy.
        Return structured fields only.
        Keep sceneCategory compact.
        Keep confidenceBand to low, mid, or high.
        """
        session = LanguageModelSession(
            model: model,
            instructions: instructions
        )
    }

    func evaluate(
        snapshot: AICoachFrameSnapshot,
        fallbackPick: AICoachDeterministicEngine.TemplatePick,
        fallbackScore: AICoachDeterministicEngine.AlignmentScore
    ) async throws -> AICoachAdvice {
        let allowedTemplates = CompositionTemplateType.supportedTemplateIDs.sorted().joined(separator: ",")
        let prompt = Prompt("""
        Analyze this camera framing state.
        allowedTemplates=\(allowedTemplates)
        activeTemplate=\(snapshot.templateID ?? "none")
        sceneSummary=\(snapshot.sceneSummary)
        semanticSignals=\(snapshot.semanticSignalSummary)
        structuralTags=\(snapshot.structuralTags.joined(separator: ","))
        subject=(\(snapshot.subjectX?.description ?? "nil"),\(snapshot.subjectY?.description ?? "nil"))
        target=(\(snapshot.targetX?.description ?? "nil"),\(snapshot.targetY?.description ?? "nil"))
        drift=(\(snapshot.stableDx),\(snapshot.stableDy))
        confidence=\(snapshot.confidence)
        lost=\(snapshot.isLost)
        """)
        let options = GenerationOptions(temperature: 0.0)
        let response = try await session.respond(
            to: prompt,
            generating: AICoachSemanticOutput.self,
            options: options
        )

        let generated = Self.extractGeneratedOutput(from: response) ?? AICoachSemanticOutput(
            sceneCategory: "fallback",
            recommendedTemplateID: fallbackPick.templateID,
            confidenceBand: "mid"
        )
        let canonicalTemplate = CompositionTemplateType.canonicalID(for: generated.recommendedTemplateID)
        let parsedPick = AICoachDeterministicEngine.validatedTemplatePick(
            fmTemplateID: canonicalTemplate,
            sceneCategory: generated.sceneCategory,
            confidenceBand: generated.confidenceBand,
            snapshot: snapshot,
            fallback: fallbackPick
        )

        return AICoachAdvice(
            instruction: fallbackScore.instruction,
            score: fallbackScore.score,
            shouldHold: fallbackScore.shouldHold,
            reason: fallbackScore.reason,
            suggestedTemplateID: parsedPick.templateID,
            suggestedTemplateReason: parsedPick.reason,
            availabilityMessage: nil,
            usedFoundationModel: true
        )
    }

    private static func extractGeneratedOutput(from response: Any) -> AICoachSemanticOutput? {
        if let direct = response as? AICoachSemanticOutput {
            return direct
        }
        let mirror = Mirror(reflecting: response)
        for child in mirror.children {
            if child.label == "content", let content = child.value as? AICoachSemanticOutput {
                return content
            }
        }
        return nil
    }
}
#endif

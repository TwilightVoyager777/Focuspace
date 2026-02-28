@preconcurrency import AVFoundation
import CoreGraphics
import Foundation

struct FrameGuidanceEvaluation {
    let rawDx: CGFloat
    let rawDy: CGFloat
    let rawStrength: CGFloat
    let rawConfidence: CGFloat
    let stableDx: CGFloat
    let stableDy: CGFloat
    let isHolding: Bool
    let targetPoint: CGPoint?
    let diagonalType: DiagonalType?
    let negativeSpaceZone: CGRect?
    let canonicalTemplateID: String?
}

final class FrameGuidanceCoordinator {
    private let templateRuleEngine = TemplateRuleEngine()
    private var stabilizer = GuidanceStabilizer2D()

    func reset() {
        stabilizer.reset()
    }

    func evaluate(
        sampleBuffer: CMSampleBuffer,
        template: CompositionTemplateType,
        anchorNormalized: CGPoint,
        subjectCurrentNormalized: CGPoint?,
        subjectTrackConfidence: Float,
        subjectIsLost: Bool,
        faceObservation: FaceSubjectObservation?,
        userSubjectAnchorNormalized: CGPoint?,
        autoFocusAnchorNormalized: CGPoint,
        now: CFTimeInterval
    ) -> FrameGuidanceEvaluation {
        guard template != .other else {
            reset()
            return FrameGuidanceEvaluation(
                rawDx: 0,
                rawDy: 0,
                rawStrength: 0,
                rawConfidence: 0,
                stableDx: 0,
                stableDy: 0,
                isHolding: true,
                targetPoint: nil,
                diagonalType: nil,
                negativeSpaceZone: nil,
                canonicalTemplateID: nil
            )
        }

        let result = templateRuleEngine.compute(
            sampleBuffer: sampleBuffer,
            anchorNormalized: anchorNormalized,
            template: template,
            subjectCurrentNormalized: subjectCurrentNormalized,
            subjectTrackConfidence: subjectTrackConfidence,
            subjectIsLost: subjectIsLost,
            faceObservation: faceObservation,
            userSubjectAnchorNormalized: userSubjectAnchorNormalized,
            autoFocusAnchorNormalized: autoFocusAnchorNormalized
        )

        let stabilized = stabilizer.update(
            rawDx: result.guidance.dx,
            rawDy: result.guidance.dy,
            confidence: result.guidance.confidence,
            now: now
        )
        var stableDx = stabilized.0
        var stableDy = stabilized.1
        let rawDx = result.guidance.dx
        let rawDy = result.guidance.dy

        if abs(rawDx) > 0.01, stableDx * rawDx < 0 {
            stableDx = rawDx * 0.6
        }
        if abs(rawDy) > 0.01, stableDy * rawDy < 0 {
            stableDy = rawDy * 0.6
        }

        return FrameGuidanceEvaluation(
            rawDx: rawDx,
            rawDy: rawDy,
            rawStrength: result.guidance.strength,
            rawConfidence: result.guidance.confidence,
            stableDx: stableDx,
            stableDy: stableDy,
            isHolding: stabilizer.isHolding,
            targetPoint: result.targetPoint,
            diagonalType: result.diagonalType,
            negativeSpaceZone: result.negativeSpaceZone,
            canonicalTemplateID: template.canonicalTemplateID
        )
    }
}

import CoreGraphics
import CoreMedia

enum TemplateType {
    case symmetry
    case center
    case thirds
    case goldenPoints
    case diagonal
    case negativeSpace
    case other

    init(id: String?) {
        switch id {
        case "symmetry":
            self = .symmetry
        case "center":
            self = .center
        case "rule_of_thirds", "thirds":
            self = .thirds
        case "golden_spiral", "goldenPoints":
            self = .goldenPoints
        case "diagonals", "diagonal":
            self = .diagonal
        case "negative_space", "negativeSpace":
            self = .negativeSpace
        default:
            self = .other
        }
    }
}

struct TemplateComputationResult {
    var guidance: GuidanceOutput
    var targetPoint: CGPoint?
    var diagonalType: DiagonalType?
    var negativeSpaceZone: CGRect?
}

struct TemplateRuleEngine {
    private let symmetryEngine = SymmetryRuleEngine()
    private let centerEngine = CenterRuleEngine()

    @MainActor private static var lastDebugInfo = GuidanceDebugInfo()

    @MainActor static func debugInfo() -> GuidanceDebugInfo {
        lastDebugInfo
    }

    private static func setDebugInfo(_ info: GuidanceDebugInfo) {
        Task { @MainActor in
            lastDebugInfo = info
        }
    }

    func compute(
        sampleBuffer: CMSampleBuffer,
        anchorNormalized: CGPoint,
        template: TemplateType,
        subjectCurrentNormalized: CGPoint?,
        subjectTrackConfidence: Float,
        subjectIsLost: Bool,
        userSubjectAnchorNormalized: CGPoint?,
        autoFocusAnchorNormalized: CGPoint
    ) -> TemplateComputationResult {
        let fallbackAnchor = CGPoint(
            x: clamp(anchorNormalized.x, min: 0, max: 1),
            y: clamp(anchorNormalized.y, min: 0, max: 1)
        )

        let resolved = resolveSubjectPoint(
            subjectCurrent: subjectCurrentNormalized,
            subjectIsLost: subjectIsLost,
            subjectTrackConfidence: subjectTrackConfidence,
            userAnchor: userSubjectAnchorNormalized,
            autoFocusAnchorNormalized: autoFocusAnchorNormalized
        )

        var base = GuidanceOutput(dx: 0, dy: 0, strength: 0, confidence: 0)
        var boundsAnchor = fallbackAnchor
        var debugDiagonal: DiagonalType? = nil
        var debugNegativeZone: CGRect? = nil
        var overlayTargetPoint: CGPoint? = nil
        switch template {
        case .symmetry:
            let subject = resolved.point
            let result = symmetryEngine.compute(sampleBuffer: sampleBuffer, anchorNormalized: subject)
            base = GuidanceOutput(
                dx: result.dx,
                dy: 0,
                strength: result.strength,
                confidence: result.confidence
            )
            boundsAnchor = subject
        case .center:
            let subject = resolved.point
            overlayTargetPoint = CGPoint(x: 0.5, y: 0.5)
            var dx = (0.5 - subject.x)
            var dy = (0.5 - subject.y)
            dx = clamp(dx, min: -1, max: 1)
            dy = clamp(dy, min: -1, max: 1)
            let strength = min(1, sqrt(dx * dx + dy * dy))
            base = GuidanceOutput(dx: dx, dy: dy, strength: strength, confidence: resolved.confidence)
            boundsAnchor = subject
        case .thirds:
            let subject = resolved.point
            let targets: [CGPoint] = [
                CGPoint(x: 1.0 / 3.0, y: 1.0 / 3.0),
                CGPoint(x: 2.0 / 3.0, y: 1.0 / 3.0),
                CGPoint(x: 1.0 / 3.0, y: 2.0 / 3.0),
                CGPoint(x: 2.0 / 3.0, y: 2.0 / 3.0)
            ]
            var bestTarget = targets[0]
            var bestDistance = squaredDistance(subject, targets[0])
            for target in targets.dropFirst() {
                let d = squaredDistance(subject, target)
                if d < bestDistance {
                    bestDistance = d
                    bestTarget = target
                }
            }
            overlayTargetPoint = bestTarget

            var dx = (bestTarget.x - subject.x)
            var dy = (bestTarget.y - subject.y)
            dx = clamp(dx, min: -1, max: 1)
            dy = clamp(dy, min: -1, max: 1)
            let strength = min(1, sqrt(dx * dx + dy * dy))
            base = GuidanceOutput(dx: dx, dy: dy, strength: strength, confidence: resolved.confidence)
            boundsAnchor = subject
        case .goldenPoints:
            let subject = resolved.point
            let a: CGFloat = 0.382
            let b: CGFloat = 0.618
            let targets: [CGPoint] = [
                CGPoint(x: a, y: a),
                CGPoint(x: b, y: a),
                CGPoint(x: a, y: b),
                CGPoint(x: b, y: b)
            ]
            var bestTarget = targets[0]
            var bestDistance = squaredDistance(subject, targets[0])
            for target in targets.dropFirst() {
                let d = squaredDistance(subject, target)
                if d < bestDistance {
                    bestDistance = d
                    bestTarget = target
                }
            }
            overlayTargetPoint = bestTarget

            var dx = (bestTarget.x - subject.x)
            var dy = (bestTarget.y - subject.y)
            dx = clamp(dx, min: -1, max: 1)
            dy = clamp(dy, min: -1, max: 1)
            let strength = min(1, sqrt(dx * dx + dy * dy))
            base = GuidanceOutput(dx: dx, dy: dy, strength: strength, confidence: resolved.confidence)
            boundsAnchor = subject
        case .diagonal:
            let subject = resolved.point
            let t1 = (subject.x + subject.y) / 2
            let q1 = CGPoint(x: t1, y: t1)
            let t2 = (subject.x - subject.y + 1) / 2
            let q2 = CGPoint(x: t2, y: 1 - t2)
            let c1 = CGPoint(x: clamp(q1.x, min: 0, max: 1), y: clamp(q1.y, min: 0, max: 1))
            let c2 = CGPoint(x: clamp(q2.x, min: 0, max: 1), y: clamp(q2.y, min: 0, max: 1))
            let isMain = squaredDistance(subject, c1) <= squaredDistance(subject, c2)
            let chosen = isMain ? c1 : c2
            debugDiagonal = isMain ? .main : .anti
            overlayTargetPoint = chosen

            var dx = (chosen.x - subject.x)
            var dy = (chosen.y - subject.y)
            dx = clamp(dx, min: -1, max: 1)
            dy = clamp(dy, min: -1, max: 1)
            let strength = min(1, sqrt(dx * dx + dy * dy))
            base = GuidanceOutput(dx: dx, dy: dy, strength: strength, confidence: resolved.confidence)
            boundsAnchor = subject
        case .negativeSpace:
            let subject = resolved.point
            debugNegativeZone = negativeSpaceZoneRect(anchorNormalized: subject)
            if let zone = debugNegativeZone {
                overlayTargetPoint = closestPointInRect(subject, zone)
            }
            base = negativeSpaceGuidance(anchorNormalized: subject, confidence: resolved.confidence)
            boundsAnchor = subject
        case .other:
            base = GuidanceOutput(dx: 0, dy: 0, strength: 0, confidence: 0)
            boundsAnchor = fallbackAnchor
        }

        let bounded = applyBoundsConstraint(anchor: boundsAnchor, guidance: base)
        let subjectPoint = resolved.point
        let debugTargetPoint = CGPoint(
            x: clamp(subjectPoint.x + bounded.dx, min: 0, max: 1),
            y: clamp(subjectPoint.y + bounded.dy, min: 0, max: 1)
        )
        let gTemplate = CGSize(width: bounded.dx, height: bounded.dy)
        let errMag = sqrt(bounded.dx * bounded.dx + bounded.dy * bounded.dy)
        let templateLabel: String
        switch template {
        case .symmetry:
            templateLabel = "symmetry"
        case .center:
            templateLabel = "center"
        case .thirds:
            templateLabel = "rule_of_thirds"
        case .goldenPoints:
            templateLabel = "golden_spiral"
        case .diagonal:
            templateLabel = "diagonals"
        case .negativeSpace:
            templateLabel = "negative_space"
        case .other:
            templateLabel = "other"
        }
        let debugInfo = GuidanceDebugInfo(
            templateType: templateLabel,
            subjectPoint: subjectPoint,
            targetPoint: debugTargetPoint,
            gTemplate: gTemplate,
            templateConfidence: bounded.confidence,
            errMag: errMag,
            subjectSource: resolved.source,
            diagonalType: debugDiagonal,
            negativeSpaceZone: debugNegativeZone
        )
        TemplateRuleEngine.setDebugInfo(debugInfo)
        return TemplateComputationResult(
            guidance: bounded,
            targetPoint: overlayTargetPoint,
            diagonalType: debugDiagonal,
            negativeSpaceZone: debugNegativeZone
        )
    }

    private func resolveSubjectPoint(
        subjectCurrent: CGPoint?,
        subjectIsLost: Bool,
        subjectTrackConfidence: Float,
        userAnchor: CGPoint?,
        autoFocusAnchorNormalized: CGPoint
    ) -> (point: CGPoint, confidence: CGFloat, source: String) {
        if subjectIsLost == false, let subjectCurrent {
            let clamped = CGPoint(
                x: clamp(subjectCurrent.x, min: 0, max: 1),
                y: clamp(subjectCurrent.y, min: 0, max: 1)
            )
            return (clamped, clamp(CGFloat(subjectTrackConfidence), min: 0, max: 1), "vision")
        }
        if let userAnchor {
            let clamped = CGPoint(
                x: clamp(userAnchor.x, min: 0, max: 1),
                y: clamp(userAnchor.y, min: 0, max: 1)
            )
            return (clamped, 1.0, "tap")
        }
        let clampedAuto = CGPoint(
            x: clamp(autoFocusAnchorNormalized.x, min: 0, max: 1),
            y: clamp(autoFocusAnchorNormalized.y, min: 0, max: 1)
        )
        return (clampedAuto, 0.6, "auto")
    }

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(value, max))
    }

    private func squaredDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }

    private func closestPointInRect(_ p: CGPoint, _ rect: CGRect) -> CGPoint {
        CGPoint(
            x: clamp(p.x, min: rect.minX, max: rect.maxX),
            y: clamp(p.y, min: rect.minY, max: rect.maxY)
        )
    }

    private func negativeSpaceGuidance(anchorNormalized: CGPoint, confidence: CGFloat) -> GuidanceOutput {
        let rect = negativeSpaceZoneRect(anchorNormalized: anchorNormalized)
        let target = closestPointInRect(anchorNormalized, rect)
        var dx = (target.x - anchorNormalized.x)
        var dy = (target.y - anchorNormalized.y)
        dx = clamp(dx, min: -1, max: 1)
        dy = clamp(dy, min: -1, max: 1)
        let strength = min(1, sqrt(dx * dx + dy * dy))
        return GuidanceOutput(dx: dx, dy: dy, strength: strength, confidence: confidence)
    }

    private func negativeSpaceZoneRect(anchorNormalized: CGPoint) -> CGRect {
        let vx = anchorNormalized.x - 0.5
        let vy = anchorNormalized.y - 0.5

        let minX: CGFloat
        let maxX: CGFloat
        let minY: CGFloat
        let maxY: CGFloat

        if abs(vx) >= abs(vy) {
            if vx < 0 {
                minX = 0.62
                maxX = 0.85
                minY = 0.15
                maxY = 0.85
            } else {
                minX = 0.15
                maxX = 0.38
                minY = 0.15
                maxY = 0.85
            }
        } else {
            if vy < 0 {
                minX = 0.15
                maxX = 0.85
                minY = 0.62
                maxY = 0.85
            } else {
                minX = 0.15
                maxX = 0.85
                minY = 0.15
                maxY = 0.38
            }
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func applyBoundsConstraint(
        anchor: CGPoint,
        guidance: GuidanceOutput,
        margin m: CGFloat = 0.10,
        weight w: CGFloat = 3.0
    ) -> GuidanceOutput {
        var bx: CGFloat = 0
        var by: CGFloat = 0

        if anchor.x < m {
            bx = m - anchor.x
        } else if anchor.x > 1 - m {
            bx = -(anchor.x - (1 - m))
        }

        if anchor.y < m {
            by = m - anchor.y
        } else if anchor.y > 1 - m {
            by = -(anchor.y - (1 - m))
        }

        var dx = guidance.dx + w * bx
        var dy = guidance.dy + w * by
        dx = clamp(dx, min: -1, max: 1)
        dy = clamp(dy, min: -1, max: 1)
        let strength = min(1, sqrt(dx * dx + dy * dy))
        return GuidanceOutput(dx: dx, dy: dy, strength: strength, confidence: guidance.confidence)
    }
}

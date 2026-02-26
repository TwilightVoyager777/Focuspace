import CoreGraphics
import CoreMedia

enum TemplateType {
    case symmetry
    case center
    case leadingLines
    case framing
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
        var boundsMargin: CGFloat = 0.10
        var boundsWeight: CGFloat = 3.0
        var debugDiagonal: DiagonalType? = nil
        var debugNegativeZone: CGRect? = nil
        var overlayTargetPoint: CGPoint? = nil
        switch template {
        case .symmetry:
            let subject = resolved.point
            let result = symmetryEngine.compute(sampleBuffer: sampleBuffer, anchorNormalized: subject)
            let target = CGPoint(x: 0.5, y: subject.y)
            overlayTargetPoint = target
            let geometricDx = target.x - subject.x
            let blendedDx = (result.dx * 0.75) + (geometricDx * 0.25)
            let blendedConfidence = clamp(
                (result.confidence * 0.7) + (resolved.confidence * 0.3),
                min: 0,
                max: 1
            )
            base = tunedGuidance(
                rawDx: blendedDx,
                rawDy: 0,
                confidence: blendedConfidence,
                gainX: 1.15,
                gainY: 0,
                deadZone: 0.020,
                activeRange: 0.34,
                confidenceFloor: 0.22
            )
            boundsMargin = 0.08
            boundsWeight = 2.6
            boundsAnchor = subject
        case .center:
            let subject = resolved.point
            let target = CGPoint(x: 0.5, y: 0.5)
            overlayTargetPoint = target
            let centerResult = centerEngine.compute(sampleBuffer: sampleBuffer, anchorNormalized: subject)
            let geometricDx = target.x - subject.x
            let geometricDy = target.y - subject.y
            let imageWeight: CGFloat
            switch resolved.source {
            case "tap", "vision":
                imageWeight = 0.0
            default:
                imageWeight = 0.30
            }
            let geometricWeight = 1 - imageWeight
            var blendedDx = (geometricDx * geometricWeight) + (centerResult.dx * imageWeight)
            var blendedDy = (geometricDy * geometricWeight) + (centerResult.dy * imageWeight)
            if abs(geometricDx) > 0.001, blendedDx * geometricDx < 0 {
                blendedDx = geometricDx
            }
            if abs(geometricDy) > 0.001, blendedDy * geometricDy < 0 {
                blendedDy = geometricDy
            }
            let blendedConfidence = clamp(
                (resolved.confidence * geometricWeight) + (centerResult.confidence * imageWeight),
                min: 0,
                max: 1
            )
            base = tunedGuidance(
                rawDx: blendedDx,
                rawDy: blendedDy,
                confidence: blendedConfidence,
                gainX: 1.0,
                gainY: 1.0,
                deadZone: 0.028,
                activeRange: 0.30,
                confidenceFloor: 0.18
            )
            boundsMargin = 0.09
            boundsWeight = 2.4
            boundsAnchor = subject
        case .leadingLines:
            let subject = resolved.point
            let target = CGPoint(x: 0.66, y: 0.33)
            overlayTargetPoint = target
            let geometricDx = target.x - subject.x
            let geometricDy = target.y - subject.y
            base = tunedGuidance(
                rawDx: geometricDx,
                rawDy: geometricDy,
                confidence: resolved.confidence,
                gainX: 1.05,
                gainY: 1.05,
                deadZone: 0.030,
                activeRange: 0.38,
                confidenceFloor: 0.18
            )
            boundsMargin = 0.09
            boundsWeight = 2.2
            boundsAnchor = subject
        case .framing:
            let subject = resolved.point
            let frameRect = CGRect(x: 0.20, y: 0.20, width: 0.60, height: 0.60)
            let center = CGPoint(x: 0.5, y: 0.5)
            let inFrameTarget = closestPointInRect(subject, frameRect)
            let target = CGPoint(
                x: (inFrameTarget.x * 0.8) + (center.x * 0.2),
                y: (inFrameTarget.y * 0.8) + (center.y * 0.2)
            )
            overlayTargetPoint = target
            base = tunedGuidance(
                rawDx: target.x - subject.x,
                rawDy: target.y - subject.y,
                confidence: resolved.confidence,
                gainX: 0.95,
                gainY: 0.95,
                deadZone: 0.028,
                activeRange: 0.30,
                confidenceFloor: 0.18
            )
            boundsMargin = 0.10
            boundsWeight = 2.1
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
            let nearest = nearestTarget(to: subject, in: targets)
            let smoothed = weightedTarget(to: subject, in: targets, softness: 0.14)
            let target = CGPoint(
                x: (nearest.x * 0.72) + (smoothed.x * 0.28),
                y: (nearest.y * 0.72) + (smoothed.y * 0.28)
            )
            overlayTargetPoint = target
            let dx = target.x - subject.x
            let dy = target.y - subject.y
            base = tunedGuidance(
                rawDx: dx,
                rawDy: dy,
                confidence: resolved.confidence,
                gainX: 1.0,
                gainY: 1.0,
                deadZone: 0.024,
                activeRange: 0.32,
                confidenceFloor: 0.20
            )
            boundsMargin = 0.09
            boundsWeight = 2.2
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

        var bounded = applyBoundsConstraint(
            anchor: boundsAnchor,
            guidance: base,
            margin: boundsMargin,
            weight: boundsWeight
        )
        let subjectPoint = resolved.point
        bounded = enforceDirectionConsistency(
            guidance: bounded,
            subject: subjectPoint,
            target: overlayTargetPoint
        )
        let debugTargetPoint = overlayTargetPoint ?? CGPoint(
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
        case .leadingLines:
            templateLabel = "leading_lines"
        case .framing:
            templateLabel = "framing"
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

    private func nearestTarget(to subject: CGPoint, in candidates: [CGPoint]) -> CGPoint {
        guard let first = candidates.first else {
            return subject
        }
        var best = first
        var bestDistance = squaredDistance(subject, first)
        for candidate in candidates.dropFirst() {
            let distance = squaredDistance(subject, candidate)
            if distance < bestDistance {
                bestDistance = distance
                best = candidate
            }
        }
        return best
    }

    private func weightedTarget(to subject: CGPoint, in candidates: [CGPoint], softness: CGFloat) -> CGPoint {
        guard !candidates.isEmpty else {
            return subject
        }
        let s2 = max(softness * softness, 0.0001)
        var sumW: CGFloat = 0
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0

        for point in candidates {
            let d2 = squaredDistance(subject, point)
            let w = 1.0 / (d2 + s2)
            sumW += w
            sumX += point.x * w
            sumY += point.y * w
        }

        guard sumW > 0 else {
            return subject
        }

        return CGPoint(x: sumX / sumW, y: sumY / sumW)
    }

    private func tunedGuidance(
        rawDx: CGFloat,
        rawDy: CGFloat,
        confidence: CGFloat,
        gainX: CGFloat,
        gainY: CGFloat,
        deadZone: CGFloat,
        activeRange: CGFloat,
        confidenceFloor: CGFloat
    ) -> GuidanceOutput {
        var dx = clamp(rawDx * gainX, min: -1, max: 1)
        var dy = clamp(rawDy * gainY, min: -1, max: 1)
        let magnitude = sqrt(dx * dx + dy * dy)
        let confidenceScale = confidenceRamp(confidence, floor: confidenceFloor)

        if magnitude < deadZone || confidenceScale <= 0 {
            return GuidanceOutput(dx: 0, dy: 0, strength: 0, confidence: confidence)
        }

        let t = smoothstep((magnitude - deadZone) / max(0.001, activeRange))
        let scale = (0.42 + 0.58 * t) * confidenceScale
        dx *= scale
        dy *= scale

        let outputMag = sqrt(dx * dx + dy * dy)
        let strength = clamp(outputMag / max(0.001, activeRange), min: 0, max: 1)
        return GuidanceOutput(dx: dx, dy: dy, strength: strength, confidence: confidence)
    }

    private func smoothstep(_ x: CGFloat) -> CGFloat {
        let t = clamp(x, min: 0, max: 1)
        return t * t * (3 - 2 * t)
    }

    private func confidenceRamp(_ confidence: CGFloat, floor: CGFloat) -> CGFloat {
        guard confidence > floor else { return 0 }
        let t = (confidence - floor) / max(0.001, 1 - floor)
        return smoothstep(t)
    }

    private func enforceDirectionConsistency(
        guidance: GuidanceOutput,
        subject: CGPoint,
        target: CGPoint?,
        epsilon: CGFloat = 0.01
    ) -> GuidanceOutput {
        guard let target else { return guidance }

        let expectedDx = target.x - subject.x
        let expectedDy = target.y - subject.y
        var dx = guidance.dx
        var dy = guidance.dy

        if abs(expectedDx) > epsilon, dx * expectedDx < 0 {
            let correctedAbs = max(abs(dx), min(0.2, abs(expectedDx) * 0.6))
            dx = correctedAbs * (expectedDx > 0 ? 1 : -1)
        }

        if abs(expectedDy) > epsilon, dy * expectedDy < 0 {
            let correctedAbs = max(abs(dy), min(0.2, abs(expectedDy) * 0.6))
            dy = correctedAbs * (expectedDy > 0 ? 1 : -1)
        }

        dx = clamp(dx, min: -1, max: 1)
        dy = clamp(dy, min: -1, max: 1)
        let strength = min(1, sqrt(dx * dx + dy * dy))
        return GuidanceOutput(dx: dx, dy: dy, strength: strength, confidence: guidance.confidence)
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

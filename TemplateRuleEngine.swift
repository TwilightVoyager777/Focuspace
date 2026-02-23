import CoreGraphics
import CoreMedia

enum TemplateType {
    case symmetry
    case center
    case thirds
    case goldenPoints
    case diagonal
    case negativeSpaceLeft
    case negativeSpaceRight
    case negativeSpaceTop
    case negativeSpaceBottom
    case other

    init(id: String?) {
        switch id {
        case "symmetry":
            self = .symmetry
        case "center":
            self = .center
        case "thirds":
            self = .thirds
        case "goldenPoints":
            self = .goldenPoints
        case "diagonal":
            self = .diagonal
        case "negativeSpaceLeft":
            self = .negativeSpaceLeft
        case "negativeSpaceRight":
            self = .negativeSpaceRight
        case "negativeSpaceTop":
            self = .negativeSpaceTop
        case "negativeSpaceBottom":
            self = .negativeSpaceBottom
        default:
            self = .other
        }
    }
}

struct TemplateRuleEngine {
    private let symmetryEngine = SymmetryRuleEngine()
    private let centerEngine = CenterRuleEngine()

    func compute(
        sampleBuffer: CMSampleBuffer,
        anchorNormalized: CGPoint,
        template: TemplateType
    ) -> GuidanceOutput {
        let anchor = CGPoint(
            x: clamp(anchorNormalized.x, min: 0, max: 1),
            y: clamp(anchorNormalized.y, min: 0, max: 1)
        )

        let base: GuidanceOutput
        switch template {
        case .symmetry:
            let result = symmetryEngine.compute(sampleBuffer: sampleBuffer, anchorNormalized: anchor)
            base = GuidanceOutput(
                dx: result.dx,
                dy: 0,
                strength: result.strength,
                confidence: result.confidence
            )
        case .center:
            let result = centerEngine.compute(sampleBuffer: sampleBuffer, anchorNormalized: anchor)
            base = GuidanceOutput(
                dx: result.dx,
                dy: result.dy,
                strength: result.strength,
                confidence: result.confidence
            )
        case .thirds:
            let targets: [CGPoint] = [
                CGPoint(x: 1.0 / 3.0, y: 1.0 / 3.0),
                CGPoint(x: 2.0 / 3.0, y: 1.0 / 3.0),
                CGPoint(x: 1.0 / 3.0, y: 2.0 / 3.0),
                CGPoint(x: 2.0 / 3.0, y: 2.0 / 3.0)
            ]
            var bestTarget = targets[0]
            var bestDistance = squaredDistance(anchor, targets[0])
            for target in targets.dropFirst() {
                let d = squaredDistance(anchor, target)
                if d < bestDistance {
                    bestDistance = d
                    bestTarget = target
                }
            }

            var dx = (bestTarget.x - anchor.x) * 1.6
            var dy = (bestTarget.y - anchor.y) * 1.6
            dx = clamp(dx, min: -1, max: 1)
            dy = clamp(dy, min: -1, max: 1)
            let strength = min(1, sqrt(dx * dx + dy * dy))
            base = GuidanceOutput(dx: dx, dy: dy, strength: strength, confidence: 1)
        case .goldenPoints:
            let a: CGFloat = 0.382
            let b: CGFloat = 0.618
            let targets: [CGPoint] = [
                CGPoint(x: a, y: a),
                CGPoint(x: b, y: a),
                CGPoint(x: a, y: b),
                CGPoint(x: b, y: b)
            ]
            var bestTarget = targets[0]
            var bestDistance = squaredDistance(anchor, targets[0])
            for target in targets.dropFirst() {
                let d = squaredDistance(anchor, target)
                if d < bestDistance {
                    bestDistance = d
                    bestTarget = target
                }
            }

            var dx = (bestTarget.x - anchor.x) * 1.6
            var dy = (bestTarget.y - anchor.y) * 1.6
            dx = clamp(dx, min: -1, max: 1)
            dy = clamp(dy, min: -1, max: 1)
            let strength = min(1, sqrt(dx * dx + dy * dy))
            base = GuidanceOutput(dx: dx, dy: dy, strength: strength, confidence: 1)
        case .diagonal:
            let t1 = (anchor.x + anchor.y) / 2
            let q1 = CGPoint(x: t1, y: t1)
            let t2 = (anchor.x - anchor.y + 1) / 2
            let q2 = CGPoint(x: t2, y: 1 - t2)
            let c1 = CGPoint(x: clamp(q1.x, min: 0, max: 1), y: clamp(q1.y, min: 0, max: 1))
            let c2 = CGPoint(x: clamp(q2.x, min: 0, max: 1), y: clamp(q2.y, min: 0, max: 1))
            let chosen = squaredDistance(anchor, c1) <= squaredDistance(anchor, c2) ? c1 : c2

            var dx = (chosen.x - anchor.x) * 2.0
            var dy = (chosen.y - anchor.y) * 2.0
            dx = clamp(dx, min: -1, max: 1)
            dy = clamp(dy, min: -1, max: 1)
            let strength = min(1, sqrt(dx * dx + dy * dy))
            base = GuidanceOutput(dx: dx, dy: dy, strength: strength, confidence: 1)
        case .negativeSpaceLeft:
            base = negativeSpaceGuidance(
                anchorNormalized: anchor,
                minX: 0.62,
                maxX: 0.85,
                minY: 0.15,
                maxY: 0.85
            )
        case .negativeSpaceRight:
            base = negativeSpaceGuidance(
                anchorNormalized: anchor,
                minX: 0.15,
                maxX: 0.38,
                minY: 0.15,
                maxY: 0.85
            )
        case .negativeSpaceTop:
            base = negativeSpaceGuidance(
                anchorNormalized: anchor,
                minX: 0.15,
                maxX: 0.85,
                minY: 0.62,
                maxY: 0.85
            )
        case .negativeSpaceBottom:
            base = negativeSpaceGuidance(
                anchorNormalized: anchor,
                minX: 0.15,
                maxX: 0.85,
                minY: 0.15,
                maxY: 0.38
            )
        case .other:
            base = GuidanceOutput(dx: 0, dy: 0, strength: 0, confidence: 0)
        }

        return applyBoundsConstraint(anchor: anchor, guidance: base)
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

    private func negativeSpaceGuidance(
        anchorNormalized: CGPoint,
        minX: CGFloat,
        maxX: CGFloat,
        minY: CGFloat,
        maxY: CGFloat
    ) -> GuidanceOutput {
        let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let target = closestPointInRect(anchorNormalized, rect)
        var dx = (target.x - anchorNormalized.x) * 2.0
        var dy = (target.y - anchorNormalized.y) * 2.0
        dx = clamp(dx, min: -1, max: 1)
        dy = clamp(dy, min: -1, max: 1)
        let strength = min(1, sqrt(dx * dx + dy * dy))
        return GuidanceOutput(dx: dx, dy: dy, strength: strength, confidence: 1)
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

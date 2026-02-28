import CoreGraphics

extension TemplateRuleEngine {
    func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(value, max))
    }

    func squaredDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }

    func nearestTarget(to subject: CGPoint, in candidates: [CGPoint]) -> CGPoint {
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

    func weightedTarget(to subject: CGPoint, in candidates: [CGPoint], softness: CGFloat) -> CGPoint {
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

    func bestScoredCandidate(
        subject: CGPoint,
        candidates: [CGPoint],
        scoring: (CGPoint) -> CGFloat
    ) -> CGPoint {
        guard let first = candidates.first else {
            return subject
        }

        var best = first
        var bestScore = scoring(first)
        for candidate in candidates.dropFirst() {
            let score = scoring(candidate)
            if score > bestScore {
                best = candidate
                bestScore = score
            }
        }
        return best
    }

    func movementEconomyScore(subject: CGPoint, target: CGPoint, idealDistance: CGFloat) -> CGFloat {
        let distance = sqrt(squaredDistance(subject, target))
        let normalized = clamp(distance / max(0.001, idealDistance), min: 0, max: 1.6)
        return 1 - smoothstep(normalized / 1.6)
    }

    func edgeSafetyScore(for point: CGPoint, margin: CGFloat) -> CGFloat {
        let nearestEdge = min(point.x, 1 - point.x, point.y, 1 - point.y)
        let normalized = clamp((nearestEdge - margin) / max(0.001, 0.5 - margin), min: 0, max: 1)
        return smoothstep(normalized)
    }

    func sideConsistencyScore(subject: CGPoint, target: CGPoint) -> CGFloat {
        let sameHorizontalSide = (subject.x - 0.5) * (target.x - 0.5) >= 0
        let sameVerticalSide = (subject.y - 0.5) * (target.y - 0.5) >= 0
        let score: CGFloat
        switch (sameHorizontalSide, sameVerticalSide) {
        case (true, true):
            score = 1.0
        case (true, false), (false, true):
            score = 0.72
        case (false, false):
            score = 0.42
        }
        return score
    }

    func weightedScore(_ components: [(value: CGFloat, weight: CGFloat)]) -> CGFloat {
        var weightedTotal: CGFloat = 0
        var totalWeight: CGFloat = 0

        for component in components {
            weightedTotal += component.value * component.weight
            totalWeight += component.weight
        }

        guard totalWeight > 0 else {
            return 0
        }
        return weightedTotal / totalWeight
    }

    func tunedGuidance(
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

    func smoothstep(_ x: CGFloat) -> CGFloat {
        let t = clamp(x, min: 0, max: 1)
        return t * t * (3 - 2 * t)
    }

    func confidenceRamp(_ confidence: CGFloat, floor: CGFloat) -> CGFloat {
        guard confidence > floor else { return 0 }
        let t = (confidence - floor) / max(0.001, 1 - floor)
        return smoothstep(t)
    }

    func enforceDirectionConsistency(
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

    func closestPointInRect(_ p: CGPoint, _ rect: CGRect) -> CGPoint {
        CGPoint(
            x: clamp(p.x, min: rect.minX, max: rect.maxX),
            y: clamp(p.y, min: rect.minY, max: rect.maxY)
        )
    }
}

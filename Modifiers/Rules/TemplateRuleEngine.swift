import CoreGraphics
import CoreMedia
import CoreVideo

struct TemplateRuleEngine {
    private struct NegativeSpaceLayout {
        let target: CGPoint
        let zone: CGRect
    }

    private struct LeadingLinesAnalysis {
        let vanishingPoint: CGPoint
        let confidence: CGFloat
    }

    private struct SceneEnergyAnalysis {
        let center: CGPoint
        let confidence: CGFloat
    }

    private struct DiagonalPreferenceAnalysis {
        let preferred: DiagonalType
        let confidence: CGFloat
    }

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
        template: CompositionTemplateType,
        subjectCurrentNormalized: CGPoint?,
        subjectTrackConfidence: Float,
        subjectIsLost: Bool,
        faceObservation: FaceSubjectObservation?,
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
        var effectiveSubject = resolved

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
            let symmetryAxis = symmetryAxisTarget(for: subject, sampleBuffer: sampleBuffer)
            let target = CGPoint(x: symmetryAxis.x, y: subject.y)
            overlayTargetPoint = target
            let geometricDx = target.x - subject.x
            let geometricWeight = 0.25 + (symmetryAxis.confidence * 0.25)
            let imageWeight = 1 - geometricWeight
            let blendedDx = (result.dx * imageWeight) + (geometricDx * geometricWeight)
            let blendedConfidence = clamp(
                (result.confidence * (0.58 + symmetryAxis.confidence * 0.14)) +
                    (resolved.confidence * (0.28 - symmetryAxis.confidence * 0.08)) +
                    (symmetryAxis.confidence * 0.22),
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
            let target = leadingLinesTarget(for: subject, sampleBuffer: sampleBuffer)
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
            let target = framingTarget(for: subject)
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
            let target = ruleOfThirdsTarget(for: subject)
            overlayTargetPoint = target
            base = tunedGuidance(
                rawDx: target.x - subject.x,
                rawDy: target.y - subject.y,
                confidence: resolved.confidence,
                gainX: 1.0,
                gainY: 1.0,
                deadZone: 0.024,
                activeRange: 0.31,
                confidenceFloor: 0.20
            )
            boundsMargin = 0.09
            boundsWeight = 2.2
            boundsAnchor = subject
        case .goldenPoints:
            let subject = resolved.point
            let target = goldenSpiralTarget(for: subject, sampleBuffer: sampleBuffer)
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
            let mainDistance = squaredDistance(subject, c1)
            let antiDistance = squaredDistance(subject, c2)
            let smoothedTarget = weightedTarget(to: subject, in: [c1, c2], softness: 0.10)
            let ambiguityThreshold: CGFloat = 0.004
            let nearLockThreshold: CGFloat = 0.0012
            let distanceDiff = abs(mainDistance - antiDistance)
            let subjectPreferMain = mainDistance <= antiDistance
            let diagonalPreference = diagonalPreference(from: sampleBuffer)
            let preferMain: Bool = {
                guard let diagonalPreference else {
                    return subjectPreferMain
                }

                let preferredIsMain = diagonalPreference.preferred == .main
                if distanceDiff < ambiguityThreshold {
                    return preferredIsMain
                }

                let preferenceWeight = diagonalPreference.confidence
                if preferenceWeight > 0.42 {
                    return preferredIsMain
                }

                return subjectPreferMain
            }()
            let hardTarget = preferMain ? c1 : c2
            let target: CGPoint
            if min(mainDistance, antiDistance) < nearLockThreshold {
                debugDiagonal = subjectPreferMain ? .main : .anti
                target = subjectPreferMain ? c1 : c2
            } else if distanceDiff < ambiguityThreshold {
                // Near diagonal boundary use continuous target to suppress flip jitter.
                if let diagonalPreference, diagonalPreference.confidence > 0.24 {
                    debugDiagonal = diagonalPreference.preferred
                    let preferredTarget = diagonalPreference.preferred == .main ? c1 : c2
                    let preferenceWeight = 0.30 + diagonalPreference.confidence * 0.35
                    target = CGPoint(
                        x: (smoothedTarget.x * (1 - preferenceWeight)) + (preferredTarget.x * preferenceWeight),
                        y: (smoothedTarget.y * (1 - preferenceWeight)) + (preferredTarget.y * preferenceWeight)
                    )
                } else {
                    debugDiagonal = nil
                    target = smoothedTarget
                }
            } else {
                debugDiagonal = preferMain ? .main : .anti
                let preferenceWeight: CGFloat = {
                    guard let diagonalPreference, debugDiagonal == diagonalPreference.preferred else {
                        return 0.80
                    }
                    return clamp(0.80 + diagonalPreference.confidence * 0.12, min: 0.80, max: 0.92)
                }()
                target = CGPoint(
                    x: (hardTarget.x * preferenceWeight) + (smoothedTarget.x * (1 - preferenceWeight)),
                    y: (hardTarget.y * preferenceWeight) + (smoothedTarget.y * (1 - preferenceWeight))
                )
            }
            overlayTargetPoint = target
            base = tunedGuidance(
                rawDx: target.x - subject.x,
                rawDy: target.y - subject.y,
                confidence: resolved.confidence,
                gainX: 1.0,
                gainY: 1.0,
                deadZone: 0.022,
                activeRange: 0.28,
                confidenceFloor: 0.20
            )
            boundsMargin = 0.09
            boundsWeight = 2.0
            boundsAnchor = subject
        case .negativeSpace:
            let subject = resolved.point
            let layout = negativeSpaceLayout(anchorNormalized: subject)
            debugNegativeZone = layout.zone
            overlayTargetPoint = layout.target
            base = tunedGuidance(
                rawDx: layout.target.x - subject.x,
                rawDy: layout.target.y - subject.y,
                confidence: resolved.confidence,
                gainX: 0.95,
                gainY: 0.95,
                deadZone: 0.026,
                activeRange: 0.34,
                confidenceFloor: 0.18
            )
            boundsMargin = 0.09
            boundsWeight = 2.0
            boundsAnchor = subject
        case .portraitHeadroom:
            let portraitSubject = resolvePortraitSubjectPoint(
                base: resolved,
                faceObservation: faceObservation
            )
            effectiveSubject = portraitSubject
            let subject = portraitSubject.point
            let target = portraitHeadroomTarget(for: subject)
            overlayTargetPoint = target
            base = tunedGuidance(
                rawDx: target.x - subject.x,
                rawDy: target.y - subject.y,
                confidence: portraitSubject.confidence,
                gainX: 0.82,
                gainY: 1.12,
                deadZone: 0.024,
                activeRange: 0.30,
                confidenceFloor: 0.20
            )
            boundsMargin = 0.08
            boundsWeight = 2.2
            boundsAnchor = subject
        case .triangle:
            let subject = resolved.point
            let target = triangleTarget(for: subject)
            overlayTargetPoint = target
            base = tunedGuidance(
                rawDx: target.x - subject.x,
                rawDy: target.y - subject.y,
                confidence: resolved.confidence,
                gainX: 0.95,
                gainY: 1.00,
                deadZone: 0.024,
                activeRange: 0.33,
                confidenceFloor: 0.19
            )
            boundsMargin = 0.09
            boundsWeight = 2.1
            boundsAnchor = subject
        case .layersFMB:
            let subject = resolved.point
            let target = layersFMBTarget(for: subject)
            overlayTargetPoint = target
            base = tunedGuidance(
                rawDx: target.x - subject.x,
                rawDy: target.y - subject.y,
                confidence: resolved.confidence,
                gainX: 0.86,
                gainY: 1.08,
                deadZone: 0.025,
                activeRange: 0.34,
                confidenceFloor: 0.18
            )
            boundsMargin = 0.08
            boundsWeight = 2.0
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
        let subjectPoint = effectiveSubject.point
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
        case .portraitHeadroom:
            templateLabel = "portrait_headroom"
        case .triangle:
            templateLabel = "triangle"
        case .layersFMB:
            templateLabel = "layers_fmb"
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
            subjectSource: effectiveSubject.source,
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

    private func resolvePortraitSubjectPoint(
        base: (point: CGPoint, confidence: CGFloat, source: String),
        faceObservation: FaceSubjectObservation?
    ) -> (point: CGPoint, confidence: CGFloat, source: String) {
        guard let faceObservation else {
            return base
        }

        if let eyeLineCenter = faceObservation.eyeLineCenter {
            let point = CGPoint(
                x: clamp(eyeLineCenter.x, min: 0, max: 1),
                y: clamp(eyeLineCenter.y, min: 0, max: 1)
            )
            return (
                point,
                max(base.confidence * 0.72, faceObservation.confidence),
                "face_landmarks"
            )
        }

        let estimatedEyeLine = CGPoint(
            x: clamp(faceObservation.faceCenter.x, min: 0, max: 1),
            y: clamp(
                faceObservation.boundingBox.minY + faceObservation.boundingBox.height * 0.32,
                min: 0,
                max: 1
            )
        )
        return (
            estimatedEyeLine,
            max(base.confidence * 0.68, faceObservation.confidence * 0.92),
            "face_box"
        )
    }

    private func negativeSpaceLayout(anchorNormalized: CGPoint) -> NegativeSpaceLayout {
        let vx = anchorNormalized.x - 0.5
        let vy = anchorNormalized.y - 0.5
        let absX = abs(vx)
        let absY = abs(vy)
        let horizontalOpenness = clamp(absX / 0.38, min: 0, max: 1)
        let verticalOpenness = clamp(absY / 0.38, min: 0, max: 1)

        let horizontalTargetBand = (1 - horizontalOpenness) * 0.09 + 0.24
        let horizontalZoneWidth = (1 - horizontalOpenness) * 0.10 + 0.24
        let horizontalZoneHeight = clamp(0.80 - abs(vy) * 0.18, min: 0.62, max: 0.82)
        let horizontalZoneY = (1 - horizontalZoneHeight) * 0.5

        let leftSubjectTarget = CGPoint(
            x: horizontalTargetBand,
            y: clamp((anchorNormalized.y * 0.30) + 0.35, min: 0.22, max: 0.78)
        )
        let rightSubjectTarget = CGPoint(
            x: 1 - horizontalTargetBand,
            y: clamp((anchorNormalized.y * 0.30) + 0.35, min: 0.22, max: 0.78)
        )
        let horizontalCandidates: [NegativeSpaceLayout] = [
            NegativeSpaceLayout(
                target: leftSubjectTarget,
                zone: CGRect(x: 1 - (0.10 + horizontalZoneWidth), y: horizontalZoneY, width: horizontalZoneWidth, height: horizontalZoneHeight)
            ),
            NegativeSpaceLayout(
                target: rightSubjectTarget,
                zone: CGRect(x: 0.10, y: horizontalZoneY, width: horizontalZoneWidth, height: horizontalZoneHeight)
            )
        ]

        let verticalTargetBand = (1 - verticalOpenness) * 0.09 + 0.24
        let verticalZoneHeight = (1 - verticalOpenness) * 0.10 + 0.24
        let verticalZoneWidth = clamp(0.78 - abs(vx) * 0.18, min: 0.62, max: 0.80)
        let verticalZoneX = (1 - verticalZoneWidth) * 0.5
        let topSubjectTarget = CGPoint(
            x: clamp((anchorNormalized.x * 0.30) + 0.35, min: 0.22, max: 0.78),
            y: verticalTargetBand
        )
        let bottomSubjectTarget = CGPoint(
            x: clamp((anchorNormalized.x * 0.30) + 0.35, min: 0.22, max: 0.78),
            y: 1 - verticalTargetBand
        )
        let verticalCandidates: [NegativeSpaceLayout] = [
            NegativeSpaceLayout(
                target: topSubjectTarget,
                zone: CGRect(x: verticalZoneX, y: 1 - (0.10 + verticalZoneHeight), width: verticalZoneWidth, height: verticalZoneHeight)
            ),
            NegativeSpaceLayout(
                target: bottomSubjectTarget,
                zone: CGRect(x: verticalZoneX, y: 0.10, width: verticalZoneWidth, height: verticalZoneHeight)
            )
        ]

        let candidates = horizontalCandidates + verticalCandidates
        let dominantHorizontal = absX >= absY
        let best = candidates.max { lhs, rhs in
            negativeSpaceLayoutScore(
                subject: anchorNormalized,
                layout: lhs,
                horizontalBias: dominantHorizontal ? 1 : 0,
                verticalBias: dominantHorizontal ? 0 : 1
            ) < negativeSpaceLayoutScore(
                subject: anchorNormalized,
                layout: rhs,
                horizontalBias: dominantHorizontal ? 1 : 0,
                verticalBias: dominantHorizontal ? 0 : 1
            )
        }

        return best ?? candidates[0]
    }

    private func goldenSpiralTarget(for subject: CGPoint) -> CGPoint {
        let goldenNear: CGFloat = 0.382
        let goldenFar: CGFloat = 0.618
        let xBias = subject.x - 0.5
        let yBias = subject.y - 0.5
        let focus = CGPoint(
            x: xBias >= 0 ? goldenFar : goldenNear,
            y: yBias >= 0 ? goldenFar : goldenNear
        )

        // Approximate the spiral approach path with two corridor points that
        // converge into the selected focal quadrant before the final focus point.
        let outerX: CGFloat = xBias >= 0 ? 0.90 : 0.10
        let outerY: CGFloat = yBias >= 0 ? 0.90 : 0.10
        let horizontalCorridor = CGPoint(
            x: (focus.x * 0.74) + (outerX * 0.26),
            y: (focus.y * 0.82) + (subject.y * 0.18)
        )
        let verticalCorridor = CGPoint(
            x: (focus.x * 0.82) + (subject.x * 0.18),
            y: (focus.y * 0.74) + (outerY * 0.26)
        )
        let approachCandidates = [focus, horizontalCorridor, verticalCorridor]
        let corridorTarget = weightedTarget(to: subject, in: approachCandidates, softness: 0.12)
        let hardTarget = nearestTarget(to: subject, in: approachCandidates)

        return CGPoint(
            x: clamp((hardTarget.x * 0.56) + (corridorTarget.x * 0.44), min: 0.12, max: 0.88),
            y: clamp((hardTarget.y * 0.56) + (corridorTarget.y * 0.44), min: 0.12, max: 0.88)
        )
    }

    private func leadingLinesTarget(for subject: CGPoint) -> CGPoint {
        let xBias = subject.x - 0.5
        let horizontalFocus: CGFloat = xBias < 0 ? 0.66 : 0.34
        let verticalFocus = clamp((subject.y * 0.36) + 0.24, min: 0.26, max: 0.56)

        let vanishingZone = CGPoint(x: horizontalFocus, y: verticalFocus)
        let laneEntry = CGPoint(
            x: (horizontalFocus * 0.68) + (subject.x * 0.32),
            y: (verticalFocus * 0.42) + (subject.y * 0.58)
        )
        let shoulderGuide = CGPoint(
            x: xBias < 0 ? 0.46 : 0.54,
            y: (verticalFocus * 0.76) + (subject.y * 0.24)
        )
        let candidates = [vanishingZone, laneEntry, shoulderGuide]
        let hardTarget = nearestTarget(to: subject, in: candidates)
        let softTarget = weightedTarget(to: subject, in: candidates, softness: 0.14)

        return CGPoint(
            x: clamp((hardTarget.x * 0.58) + (softTarget.x * 0.42), min: 0.14, max: 0.86),
            y: clamp((hardTarget.y * 0.58) + (softTarget.y * 0.42), min: 0.18, max: 0.72)
        )
    }

    private func leadingLinesTarget(for subject: CGPoint, sampleBuffer: CMSampleBuffer) -> CGPoint {
        let heuristicTarget = leadingLinesTarget(for: subject)
        guard let analysis = leadingLinesAnalysis(from: sampleBuffer) else {
            return heuristicTarget
        }

        let sceneTarget = CGPoint(
            x: clamp((analysis.vanishingPoint.x * 0.74) + (subject.x * 0.26), min: 0.16, max: 0.84),
            y: clamp((analysis.vanishingPoint.y * 0.86) + (subject.y * 0.14), min: 0.22, max: 0.62)
        )
        let convergenceLaneTarget = CGPoint(
            x: clamp((analysis.vanishingPoint.x * 0.64) + (subject.x * 0.36), min: 0.16, max: 0.84),
            y: clamp((analysis.vanishingPoint.y * 0.72) + (subject.y * 0.28), min: 0.20, max: 0.68)
        )
        let sideBridgeTarget = CGPoint(
            x: clamp((heuristicTarget.x * 0.52) + (analysis.vanishingPoint.x * 0.48), min: 0.16, max: 0.84),
            y: clamp((heuristicTarget.y * 0.42) + (analysis.vanishingPoint.y * 0.58), min: 0.20, max: 0.68)
        )
        let candidates = [heuristicTarget, sceneTarget, convergenceLaneTarget, sideBridgeTarget]
        let best = bestScoredCandidate(subject: subject, candidates: candidates) { candidate in
            let convergenceScore = 1 - clamp(abs(candidate.x - analysis.vanishingPoint.x) / 0.34, min: 0, max: 1)
            let heightScore = 1 - clamp(abs(candidate.y - analysis.vanishingPoint.y) / 0.24, min: 0, max: 1)
            let movementScore = movementEconomyScore(subject: subject, target: candidate, idealDistance: 0.26)
            let edgeScore = edgeSafetyScore(for: candidate, margin: 0.14)
            let sideScore = sideConsistencyScore(subject: subject, target: candidate)
            return weightedScore([
                (convergenceScore, 0.24),
                (heightScore, 0.18),
                (movementScore, 0.22),
                (edgeScore, 0.14),
                (sideScore, 0.12),
                (analysis.confidence, 0.10)
            ])
        }
        let soft = weightedTarget(to: subject, in: [sceneTarget, convergenceLaneTarget, heuristicTarget], softness: 0.10)

        return CGPoint(
            x: clamp((best.x * 0.68) + (soft.x * 0.32), min: 0.14, max: 0.86),
            y: clamp((best.y * 0.68) + (soft.y * 0.32), min: 0.18, max: 0.72)
        )
    }

    private func symmetryAxisTarget(for subject: CGPoint, sampleBuffer: CMSampleBuffer) -> (x: CGFloat, confidence: CGFloat) {
        guard let energy = sceneEnergyCentroid(from: sampleBuffer) else {
            return (0.5, 0)
        }

        let axisWeight = clamp(0.28 + energy.confidence * 0.30, min: 0.28, max: 0.58)
        let dynamicAxisX = clamp((0.5 * (1 - axisWeight)) + (energy.center.x * axisWeight), min: 0.22, max: 0.78)
        let comfortBand = clamp(0.08 + abs(subject.x - 0.5) * 0.08, min: 0.08, max: 0.16)
        let constrainedAxisX = clamp(
            dynamicAxisX,
            min: max(0.18, subject.x - comfortBand),
            max: min(0.82, subject.x + comfortBand)
        )
        return (constrainedAxisX, energy.confidence)
    }

    private func goldenSpiralTarget(for subject: CGPoint, sampleBuffer: CMSampleBuffer) -> CGPoint {
        let heuristicTarget = goldenSpiralTarget(for: subject)
        guard let energy = sceneEnergyCentroid(from: sampleBuffer) else {
            return heuristicTarget
        }

        let combinedXBias = ((subject.x - 0.5) * 0.58) + ((energy.center.x - 0.5) * 0.42)
        let combinedYBias = ((subject.y - 0.5) * 0.58) + ((energy.center.y - 0.5) * 0.42)
        let focus = CGPoint(
            x: combinedXBias >= 0 ? 0.618 : 0.382,
            y: combinedYBias >= 0 ? 0.618 : 0.382
        )
        let flowTarget = CGPoint(
            x: clamp((focus.x * 0.72) + (energy.center.x * 0.28), min: 0.16, max: 0.84),
            y: clamp((focus.y * 0.72) + (energy.center.y * 0.28), min: 0.16, max: 0.84)
        )
        let corridorTarget = CGPoint(
            x: clamp((focus.x * 0.56) + (energy.center.x * 0.24) + (subject.x * 0.20), min: 0.14, max: 0.86),
            y: clamp((focus.y * 0.56) + (energy.center.y * 0.24) + (subject.y * 0.20), min: 0.14, max: 0.86)
        )
        let candidates = [heuristicTarget, flowTarget, focus, corridorTarget]
        let best = bestScoredCandidate(subject: subject, candidates: candidates) { candidate in
            let focusAffinity = 1 - clamp(sqrt(squaredDistance(candidate, focus)) / 0.30, min: 0, max: 1)
            let flowAffinity = 1 - clamp(sqrt(squaredDistance(candidate, flowTarget)) / 0.24, min: 0, max: 1)
            let movementScore = movementEconomyScore(subject: subject, target: candidate, idealDistance: 0.22)
            let sideScore = sideConsistencyScore(subject: subject, target: candidate)
            let edgeScore = edgeSafetyScore(for: candidate, margin: 0.12)
            return weightedScore([
                (focusAffinity, 0.24),
                (flowAffinity, 0.22),
                (movementScore, 0.18),
                (sideScore, 0.14),
                (edgeScore, 0.10),
                (energy.confidence, 0.12)
            ])
        }
        let soft = weightedTarget(to: subject, in: [heuristicTarget, flowTarget, corridorTarget], softness: 0.10)

        return CGPoint(
            x: clamp((best.x * 0.66) + (soft.x * 0.34), min: 0.12, max: 0.88),
            y: clamp((best.y * 0.66) + (soft.y * 0.34), min: 0.12, max: 0.88)
        )
    }

    private func leadingLinesAnalysis(from sampleBuffer: CMSampleBuffer) -> LeadingLinesAnalysis? {
        withBGRAImageData(from: sampleBuffer) { bytes, width, height, rowBytes in
            let step = max(8, min(width, height) / 48)
            let topY = max(step, Int(CGFloat(height) * 0.24))
            let startY = max(step, Int(CGFloat(height) * 0.34))
            let endY = min(height - step, Int(CGFloat(height) * 0.90))

            var weightedTopX: CGFloat = 0
            var weightedTopY: CGFloat = 0
            var totalWeight: CGFloat = 0
            var acceptedSamples = 0

            for y in stride(from: startY, to: endY, by: step) {
                let rowProgress = CGFloat(y - startY) / CGFloat(max(1, endY - startY))
                let rowWeight = 0.60 + (rowProgress * 0.55)

                for x in stride(from: step, to: width - step, by: step) {
                    let gx = luma(bytes: bytes, rowBytes: rowBytes, x: x + step, y: y) -
                        luma(bytes: bytes, rowBytes: rowBytes, x: x - step, y: y)
                    let gy = luma(bytes: bytes, rowBytes: rowBytes, x: x, y: y + step) -
                        luma(bytes: bytes, rowBytes: rowBytes, x: x, y: y - step)
                    let gradientMagnitude = abs(gx) + abs(gy)
                    if gradientMagnitude < 60 {
                        continue
                    }

                    var dirX = -gy
                    var dirY = gx
                    let length = sqrt((dirX * dirX) + (dirY * dirY))
                    if length < 0.001 {
                        continue
                    }

                    dirX /= length
                    dirY /= length

                    if dirY > 0 {
                        dirX = -dirX
                        dirY = -dirY
                    }

                    if dirY > -0.18 {
                        continue
                    }

                    let t = CGFloat(topY - y) / dirY
                    let projectedTopX = CGFloat(x) + (dirX * t)
                    let projectedTopXNormalized = projectedTopX / CGFloat(width)
                    if projectedTopXNormalized < -0.25 || projectedTopXNormalized > 1.25 {
                        continue
                    }

                    let magnitudeWeight = clamp(gradientMagnitude / 180, min: 0, max: 1)
                    let weight = rowWeight * magnitudeWeight
                    weightedTopX += projectedTopXNormalized * weight
                    weightedTopY += (CGFloat(topY) / CGFloat(height)) * weight
                    totalWeight += weight
                    acceptedSamples += 1
                }
            }

            guard acceptedSamples >= 8, totalWeight > 1.2 else {
                return nil
            }

            let meanTopX = clamp(weightedTopX / totalWeight, min: 0.08, max: 0.92)
            let meanTopY = clamp(weightedTopY / totalWeight, min: 0.20, max: 0.40)
            let sampleConfidence = clamp(CGFloat(acceptedSamples) / 42, min: 0, max: 1)
            let weightConfidence = clamp(totalWeight / 26, min: 0, max: 1)
            let confidence = smoothstep(sampleConfidence * weightConfidence)

            guard confidence > 0.08 else {
                return nil
            }

            return LeadingLinesAnalysis(
                vanishingPoint: CGPoint(x: meanTopX, y: meanTopY),
                confidence: confidence
            )
        }
    }

    private func sceneEnergyCentroid(from sampleBuffer: CMSampleBuffer) -> SceneEnergyAnalysis? {
        withBGRAImageData(from: sampleBuffer) { bytes, width, height, rowBytes in
            let step = max(8, min(width, height) / 56)
            var sumW: CGFloat = 0
            var sumX: CGFloat = 0
            var sumY: CGFloat = 0
            var samples = 0

            for y in stride(from: step, to: height - step, by: step) {
                for x in stride(from: step, to: width - step, by: step) {
                    let gx = luma(bytes: bytes, rowBytes: rowBytes, x: x + step, y: y) -
                        luma(bytes: bytes, rowBytes: rowBytes, x: x - step, y: y)
                    let gy = luma(bytes: bytes, rowBytes: rowBytes, x: x, y: y + step) -
                        luma(bytes: bytes, rowBytes: rowBytes, x: x, y: y - step)
                    let magnitude = abs(gx) + abs(gy)
                    if magnitude < 42 {
                        continue
                    }

                    let weight = clamp(magnitude / 160, min: 0, max: 1)
                    sumW += weight
                    sumX += (CGFloat(x) / CGFloat(width)) * weight
                    sumY += (CGFloat(y) / CGFloat(height)) * weight
                    samples += 1
                }
            }

            guard samples >= 10, sumW > 1.0 else {
                return nil
            }

            let center = CGPoint(
                x: clamp(sumX / sumW, min: 0.08, max: 0.92),
                y: clamp(sumY / sumW, min: 0.10, max: 0.90)
            )
            let sampleConfidence = clamp(CGFloat(samples) / 72, min: 0, max: 1)
            let weightConfidence = clamp(sumW / 20, min: 0, max: 1)
            let confidence = smoothstep(sampleConfidence * weightConfidence)

            guard confidence > 0.06 else {
                return nil
            }

            return SceneEnergyAnalysis(center: center, confidence: confidence)
        }
    }

    private func diagonalPreference(from sampleBuffer: CMSampleBuffer) -> DiagonalPreferenceAnalysis? {
        withBGRAImageData(from: sampleBuffer) { bytes, width, height, rowBytes in
            let step = max(8, min(width, height) / 56)
            let mainDiagonal = CGPoint(x: 0.7071, y: 0.7071)
            let antiDiagonal = CGPoint(x: 0.7071, y: -0.7071)
            var mainScore: CGFloat = 0
            var antiScore: CGFloat = 0
            var acceptedSamples = 0

            for y in stride(from: step, to: height - step, by: step) {
                for x in stride(from: step, to: width - step, by: step) {
                    let gx = luma(bytes: bytes, rowBytes: rowBytes, x: x + step, y: y) -
                        luma(bytes: bytes, rowBytes: rowBytes, x: x - step, y: y)
                    let gy = luma(bytes: bytes, rowBytes: rowBytes, x: x, y: y + step) -
                        luma(bytes: bytes, rowBytes: rowBytes, x: x, y: y - step)
                    let magnitude = abs(gx) + abs(gy)
                    if magnitude < 44 {
                        continue
                    }

                    var dirX = -gy
                    var dirY = gx
                    let length = sqrt((dirX * dirX) + (dirY * dirY))
                    if length < 0.001 {
                        continue
                    }

                    dirX /= length
                    dirY /= length
                    let weight = clamp(magnitude / 180, min: 0, max: 1)
                    let mainAlignment = abs((dirX * mainDiagonal.x) + (dirY * mainDiagonal.y))
                    let antiAlignment = abs((dirX * antiDiagonal.x) + (dirY * antiDiagonal.y))
                    mainScore += mainAlignment * weight
                    antiScore += antiAlignment * weight
                    acceptedSamples += 1
                }
            }

            let totalScore = mainScore + antiScore
            guard acceptedSamples >= 10, totalScore > 1.0 else {
                return nil
            }

            let diff = abs(mainScore - antiScore) / totalScore
            let confidence = smoothstep(clamp(diff * 2.4, min: 0, max: 1))
            guard confidence > 0.10 else {
                return nil
            }

            return DiagonalPreferenceAnalysis(
                preferred: mainScore >= antiScore ? .main : .anti,
                confidence: confidence
            )
        }
    }

    private func withBGRAImageData<T>(
        from sampleBuffer: CMSampleBuffer,
        _ body: (_ bytes: UnsafePointer<UInt8>, _ width: Int, _ height: Int, _ rowBytes: Int) -> T?
    ) -> T? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard format == kCVPixelFormatType_32BGRA else {
            return nil
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 32, height > 32 else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        return body(bytes, width, height, rowBytes)
    }

    private func luma(bytes: UnsafePointer<UInt8>, rowBytes: Int, x: Int, y: Int) -> CGFloat {
        let offset = (y * rowBytes) + (x * 4)
        let b = CGFloat(bytes[offset])
        let g = CGFloat(bytes[offset + 1])
        let r = CGFloat(bytes[offset + 2])
        return (r * 0.299) + (g * 0.587) + (b * 0.114)
    }

    private func ruleOfThirdsTarget(for subject: CGPoint) -> CGPoint {
        let x1: CGFloat = 1.0 / 3.0
        let x2: CGFloat = 2.0 / 3.0
        let y1: CGFloat = 1.0 / 3.0
        let y2: CGFloat = 2.0 / 3.0

        let intersections: [CGPoint] = [
            CGPoint(x: x1, y: y1),
            CGPoint(x: x2, y: y1),
            CGPoint(x: x1, y: y2),
            CGPoint(x: x2, y: y2)
        ]
        let intersectionTarget = nearestTarget(to: subject, in: intersections)

        let nearestX = abs(subject.x - x1) <= abs(subject.x - x2) ? x1 : x2
        let nearestY = abs(subject.y - y1) <= abs(subject.y - y2) ? y1 : y2
        let verticalLineTarget = CGPoint(x: nearestX, y: clamp(subject.y, min: 0.16, max: 0.84))
        let horizontalLineTarget = CGPoint(x: clamp(subject.x, min: 0.16, max: 0.84), y: nearestY)
        let quadrantVerticalTarget = CGPoint(
            x: nearestX,
            y: subject.y < 0.5 ? 0.42 : 0.58
        )
        let quadrantHorizontalTarget = CGPoint(
            x: subject.x < 0.5 ? 0.42 : 0.58,
            y: nearestY
        )
        let candidates = [intersectionTarget, verticalLineTarget, horizontalLineTarget, quadrantVerticalTarget, quadrantHorizontalTarget]

        let best = bestScoredCandidate(subject: subject, candidates: candidates) { candidate in
            let isIntersection = abs(candidate.x - nearestX) < 0.001 && abs(candidate.y - nearestY) < 0.001
            let lineMatchX = 1 - clamp(min(abs(candidate.x - x1), abs(candidate.x - x2)) / 0.20, min: 0, max: 1)
            let lineMatchY = 1 - clamp(min(abs(candidate.y - y1), abs(candidate.y - y2)) / 0.20, min: 0, max: 1)
            let lineAffinity = max(lineMatchX, lineMatchY)
            let intersectionAffinity = isIntersection ? 1.0 : 0.56
            let movementScore = movementEconomyScore(subject: subject, target: candidate, idealDistance: 0.24)
            let sideScore = sideConsistencyScore(subject: subject, target: candidate)
            let edgeScore = edgeSafetyScore(for: candidate, margin: 0.12)
            return weightedScore([
                (lineAffinity, 0.22),
                (intersectionAffinity, 0.28),
                (movementScore, 0.20),
                (sideScore, 0.18),
                (edgeScore, 0.12)
            ])
        }
        let soft = weightedTarget(to: subject, in: [verticalLineTarget, horizontalLineTarget, intersectionTarget], softness: 0.10)

        return CGPoint(
            x: clamp((best.x * 0.68) + (soft.x * 0.32), min: 0.14, max: 0.86),
            y: clamp((best.y * 0.68) + (soft.y * 0.32), min: 0.14, max: 0.86)
        )
    }

    private func negativeSpaceLayoutScore(
        subject: CGPoint,
        layout: NegativeSpaceLayout,
        horizontalBias: CGFloat,
        verticalBias: CGFloat
    ) -> CGFloat {
        let isHorizontal = layout.zone.width < layout.zone.height
        let axisPreference = isHorizontal ? horizontalBias : verticalBias
        let movementScore = movementEconomyScore(subject: subject, target: layout.target, idealDistance: 0.28)
        let targetSafety = edgeSafetyScore(for: layout.target, margin: 0.12)

        let zoneCenter = CGPoint(x: layout.zone.midX, y: layout.zone.midY)
        let subjectToZoneDistance = sqrt(squaredDistance(subject, zoneCenter))
        let separationScore = smoothstep(clamp(subjectToZoneDistance / 0.55, min: 0, max: 1))

        let targetSideScore: CGFloat = {
            let horizontalConsistent = (subject.x - 0.5) * (layout.target.x - 0.5) >= 0
            let verticalConsistent = (subject.y - 0.5) * (layout.target.y - 0.5) >= 0
            if isHorizontal {
                return horizontalConsistent ? 1.0 : 0.28
            }
            return verticalConsistent ? 1.0 : 0.28
        }()

        let zoneClearanceScore: CGFloat = {
            if isHorizontal {
                let subjectNearZone = subject.x >= layout.zone.minX && subject.x <= layout.zone.maxX
                return subjectNearZone ? 0.18 : 1.0
            }
            let subjectNearZone = subject.y >= layout.zone.minY && subject.y <= layout.zone.maxY
            return subjectNearZone ? 0.18 : 1.0
        }()

        return weightedScore([
            (axisPreference, 0.20),
            (movementScore, 0.18),
            (targetSafety, 0.12),
            (separationScore, 0.22),
            (targetSideScore, 0.18),
            (zoneClearanceScore, 0.10)
        ])
    }

    private func framingTarget(for subject: CGPoint) -> CGPoint {
        let frameRect = CGRect(x: 0.20, y: 0.20, width: 0.60, height: 0.60)
        let comfortRect = frameRect.insetBy(dx: 0.08, dy: 0.08)
        let lockRect = comfortRect.insetBy(dx: 0.14, dy: 0.14)
        let center = CGPoint(x: 0.5, y: 0.5)

        if lockRect.contains(subject) {
            return CGPoint(
                x: clamp((subject.x * 0.40) + (center.x * 0.60), min: comfortRect.minX, max: comfortRect.maxX),
                y: clamp((subject.y * 0.40) + (center.y * 0.60), min: comfortRect.minY, max: comfortRect.maxY)
            )
        }

        if comfortRect.contains(subject) {
            let lockTarget = closestPointInRect(subject, lockRect)
            let comfortCenter = CGPoint(x: comfortRect.midX, y: comfortRect.midY)
            let lockEdgeTarget = CGPoint(
                x: clamp((lockTarget.x * 0.82) + (subject.x * 0.18), min: lockRect.minX, max: lockRect.maxX),
                y: clamp((lockTarget.y * 0.82) + (subject.y * 0.18), min: lockRect.minY, max: lockRect.maxY)
            )
            let desiredDx = lockTarget.x - subject.x
            let desiredDy = lockTarget.y - subject.y
            let verticalPriority = abs(desiredDy) >= abs(desiredDx)

            let axisScore: (CGPoint) -> CGFloat = { candidate in
                if verticalPriority {
                    guard abs(desiredDy) > 0.001 else { return 1.0 }
                    let candidateDy = candidate.y - subject.y
                    let sameDirection = candidateDy * desiredDy >= 0
                    let travel = min(1, abs(candidateDy) / max(0.001, abs(desiredDy)))
                    return sameDirection ? (0.58 + 0.42 * travel) : max(0.04, 0.22 * (1 - travel))
                }

                guard abs(desiredDx) > 0.001 else { return 1.0 }
                let candidateDx = candidate.x - subject.x
                let sameDirection = candidateDx * desiredDx >= 0
                let travel = min(1, abs(candidateDx) / max(0.001, abs(desiredDx)))
                return sameDirection ? (0.58 + 0.42 * travel) : max(0.04, 0.22 * (1 - travel))
            }

            let best = bestScoredCandidate(
                subject: subject,
                candidates: [lockTarget, lockEdgeTarget, comfortCenter]
            ) { candidate in
                let movementScore = movementEconomyScore(subject: subject, target: candidate, idealDistance: 0.12)
                let edgeScore = edgeSafetyScore(for: candidate, margin: 0.24)
                let centerBalance = 1 - clamp(sqrt(squaredDistance(candidate, center)) / 0.28, min: 0, max: 1)
                return weightedScore([
                    (axisScore(candidate), 0.42),
                    (movementScore, 0.22),
                    (edgeScore, 0.16),
                    (centerBalance, 0.20)
                ])
            }

            return CGPoint(
                x: clamp((best.x * 0.78) + (lockTarget.x * 0.22), min: comfortRect.minX, max: comfortRect.maxX),
                y: clamp((best.y * 0.78) + (lockTarget.y * 0.22), min: comfortRect.minY, max: comfortRect.maxY)
            )
        }

        let frameTarget = closestPointInRect(subject, frameRect)
        let comfortTarget = closestPointInRect(subject, comfortRect)
        let axisRecoveryX: CGFloat = {
            if subject.x < comfortRect.minX || subject.x > comfortRect.maxX {
                return comfortTarget.x
            }
            return clamp((subject.x * 0.84) + (comfortRect.midX * 0.16), min: comfortRect.minX, max: comfortRect.maxX)
        }()
        let axisRecoveryY: CGFloat = {
            if subject.y < comfortRect.minY || subject.y > comfortRect.maxY {
                return comfortTarget.y
            }
            return clamp((subject.y * 0.84) + (comfortRect.midY * 0.16), min: comfortRect.minY, max: comfortRect.maxY)
        }()
        let axisRecoveryTarget = CGPoint(x: axisRecoveryX, y: axisRecoveryY)
        let desiredDx = comfortTarget.x - subject.x
        let desiredDy = comfortTarget.y - subject.y
        let verticalPriority = abs(desiredDy) >= abs(desiredDx)

        let axisScore: (CGPoint) -> CGFloat = { candidate in
            if verticalPriority {
                guard abs(desiredDy) > 0.001 else { return 1.0 }
                let candidateDy = candidate.y - subject.y
                let sameDirection = candidateDy * desiredDy >= 0
                let travel = min(1, abs(candidateDy) / max(0.001, abs(desiredDy)))
                return sameDirection ? (0.60 + 0.40 * travel) : max(0.02, 0.16 * (1 - travel))
            }

            guard abs(desiredDx) > 0.001 else { return 1.0 }
            let candidateDx = candidate.x - subject.x
            let sameDirection = candidateDx * desiredDx >= 0
            let travel = min(1, abs(candidateDx) / max(0.001, abs(desiredDx)))
            return sameDirection ? (0.60 + 0.40 * travel) : max(0.02, 0.16 * (1 - travel))
        }

        let best = bestScoredCandidate(
            subject: subject,
            candidates: [axisRecoveryTarget, comfortTarget, frameTarget]
        ) { candidate in
            let movementScore = movementEconomyScore(subject: subject, target: candidate, idealDistance: 0.20)
            let edgeScore = edgeSafetyScore(for: candidate, margin: 0.18)
            let centerBalance = 1 - clamp(sqrt(squaredDistance(candidate, center)) / 0.34, min: 0, max: 1)
            let candidatePriority: CGFloat = {
                if squaredDistance(candidate, axisRecoveryTarget) < 0.0001 { return 1.0 }
                if squaredDistance(candidate, comfortTarget) < 0.0001 { return 0.82 }
                return 0.52
            }()
            return weightedScore([
                (axisScore(candidate), 0.44),
                (movementScore, 0.18),
                (edgeScore, 0.14),
                (centerBalance, 0.10),
                (candidatePriority, 0.14)
            ])
        }

        return CGPoint(
            x: clamp((best.x * 0.76) + (axisRecoveryTarget.x * 0.24), min: frameRect.minX, max: frameRect.maxX),
            y: clamp((best.y * 0.76) + (axisRecoveryTarget.y * 0.24), min: frameRect.minY, max: frameRect.maxY)
        )
    }

    private func portraitHeadroomTarget(for subject: CGPoint) -> CGPoint {
        // Keep the subject close to center horizontally while adapting the
        // preferred vertical zone based on how high/low the current anchor sits.
        let desiredX: CGFloat = 0.5
        let verticalBias = subject.y - 0.5
        let upwardRoom = clamp(-verticalBias / 0.30, min: 0, max: 1)
        let downwardCorrection = clamp(verticalBias / 0.26, min: 0, max: 1)

        // When the subject rides high, preserve a bit more room below to avoid
        // over-correcting downward. When it sits low, pull more assertively up.
        let desiredY = clamp(
            0.34 + (upwardRoom * 0.05) - (downwardCorrection * 0.08),
            min: 0.28,
            max: 0.40
        )
        let xBlend = clamp(0.74 + abs(subject.x - 0.5) * 0.22, min: 0.74, max: 0.90)
        let yBlend = clamp(0.66 + downwardCorrection * 0.18 + upwardRoom * 0.08, min: 0.66, max: 0.92)
        let primaryTarget = CGPoint(
            x: clamp((subject.x * (1 - xBlend)) + (desiredX * xBlend), min: 0.12, max: 0.88),
            y: clamp((subject.y * (1 - yBlend)) + (desiredY * yBlend), min: 0.16, max: 0.70)
        )
        let centeredHeadroomTarget = CGPoint(x: 0.5, y: desiredY)
        let sideHeadroomTarget = CGPoint(
            x: subject.x < 0.5 ? 0.42 : 0.58,
            y: clamp(desiredY + 0.02, min: 0.28, max: 0.44)
        )
        let best = bestScoredCandidate(
            subject: subject,
            candidates: [primaryTarget, centeredHeadroomTarget, sideHeadroomTarget]
        ) { candidate in
            let movementScore = movementEconomyScore(subject: subject, target: candidate, idealDistance: 0.20)
            let headroomScore = 1 - clamp(abs(candidate.y - desiredY) / 0.14, min: 0, max: 1)
            let horizontalScore = 1 - clamp(abs(candidate.x - 0.5) / 0.26, min: 0, max: 1)
            let edgeScore = edgeSafetyScore(for: candidate, margin: 0.14)
            return weightedScore([
                (movementScore, 0.22),
                (headroomScore, 0.36),
                (horizontalScore, 0.24),
                (edgeScore, 0.18)
            ])
        }

        return CGPoint(
            x: clamp((best.x * 0.70) + (primaryTarget.x * 0.30), min: 0.12, max: 0.88),
            y: clamp((best.y * 0.70) + (primaryTarget.y * 0.30), min: 0.16, max: 0.70)
        )
    }

    private func triangleTarget(for subject: CGPoint) -> CGPoint {
        let apex = CGPoint(x: 0.50, y: 0.30)
        let baseLeft = CGPoint(x: 0.34, y: 0.72)
        let baseRight = CGPoint(x: 0.66, y: 0.72)
        let edgeBlend = clamp((subject.y - 0.38) / 0.30, min: 0, max: 1)

        let leftEdgeGuide = CGPoint(
            x: (apex.x * (1 - edgeBlend)) + (baseLeft.x * edgeBlend),
            y: (apex.y * (1 - edgeBlend)) + (baseLeft.y * edgeBlend)
        )
        let rightEdgeGuide = CGPoint(
            x: (apex.x * (1 - edgeBlend)) + (baseRight.x * edgeBlend),
            y: (apex.y * (1 - edgeBlend)) + (baseRight.y * edgeBlend)
        )
        let baseGuide = CGPoint(
            x: clamp(subject.x < 0.5 ? 0.40 : 0.60, min: baseLeft.x, max: baseRight.x),
            y: 0.70
        )

        let candidates = [apex, leftEdgeGuide, rightEdgeGuide, baseGuide]
        let hardTarget = bestScoredCandidate(subject: subject, candidates: candidates) { candidate in
            let isApex = squaredDistance(candidate, apex) < 0.0001
            let isBase = squaredDistance(candidate, baseGuide) < 0.0001
            let structuralScore: CGFloat
            if subject.y < 0.44 {
                structuralScore = isApex ? 1.0 : 0.62
            } else if subject.y > 0.66 {
                structuralScore = isBase ? 1.0 : 0.60
            } else {
                let wantsLeft = subject.x < 0.5
                let matchesSide = wantsLeft
                    ? squaredDistance(candidate, leftEdgeGuide) < squaredDistance(candidate, rightEdgeGuide)
                    : squaredDistance(candidate, rightEdgeGuide) <= squaredDistance(candidate, leftEdgeGuide)
                structuralScore = matchesSide ? 1.0 : 0.58
            }
            let movementScore = movementEconomyScore(subject: subject, target: candidate, idealDistance: 0.24)
            let edgeScore = edgeSafetyScore(for: candidate, margin: 0.14)
            return weightedScore([
                (structuralScore, 0.42),
                (movementScore, 0.28),
                (edgeScore, 0.14),
                (sideConsistencyScore(subject: subject, target: candidate), 0.16)
            ])
        }
        let softTarget = weightedTarget(to: subject, in: candidates, softness: 0.14)
        return CGPoint(
            x: clamp((hardTarget.x * 0.64) + (softTarget.x * 0.36), min: 0.12, max: 0.88),
            y: clamp((hardTarget.y * 0.64) + (softTarget.y * 0.36), min: 0.16, max: 0.84)
        )
    }

    private func layersFMBTarget(for subject: CGPoint) -> CGPoint {
        let verticalBias = subject.y - 0.5
        let horizontalBias = subject.x - 0.5

        let midBandCenter = clamp(
            0.54 + (verticalBias * 0.04),
            min: 0.50,
            max: 0.58
        )
        let bandHalfHeight = clamp(
            0.08 + (abs(verticalBias) * 0.04),
            min: 0.08,
            max: 0.12
        )
        let midBandMin = midBandCenter - bandHalfHeight
        let midBandMax = midBandCenter + bandHalfHeight

        let bandY: CGFloat
        if subject.y < midBandMin {
            bandY = (midBandMin * 0.72) + (subject.y * 0.28)
        } else if subject.y > midBandMax {
            bandY = (midBandMax * 0.72) + (subject.y * 0.28)
        } else {
            bandY = (subject.y * 0.18) + (midBandCenter * 0.82)
        }

        let laneCenterX = clamp(
            0.5 + (horizontalBias * 0.08),
            min: 0.44,
            max: 0.56
        )
        let laneWidth = clamp(
            0.12 - (abs(horizontalBias) * 0.04),
            min: 0.08,
            max: 0.12
        )
        let laneMinX = laneCenterX - laneWidth
        let laneMaxX = laneCenterX + laneWidth
        let adjustedX: CGFloat
        if subject.x < laneMinX {
            adjustedX = (laneMinX * 0.78) + (subject.x * 0.22)
        } else if subject.x > laneMaxX {
            adjustedX = (laneMaxX * 0.78) + (subject.x * 0.22)
        } else {
            adjustedX = (subject.x * 0.18) + (laneCenterX * 0.82)
        }

        let primaryTarget = CGPoint(
            x: clamp(adjustedX, min: 0.14, max: 0.86),
            y: clamp(bandY, min: 0.24, max: 0.78)
        )
        let centeredMidTarget = CGPoint(
            x: laneCenterX,
            y: midBandCenter
        )
        let laneEdgeTarget = CGPoint(
            x: subject.x < 0.5 ? laneMinX : laneMaxX,
            y: clamp((bandY * 0.68) + (midBandCenter * 0.32), min: 0.24, max: 0.78)
        )
        let supportDepthTarget = CGPoint(
            x: clamp((primaryTarget.x * 0.66) + 0.17, min: 0.18, max: 0.82),
            y: clamp((primaryTarget.y * 0.74) + 0.10, min: 0.28, max: 0.74)
        )
        let candidates = [primaryTarget, centeredMidTarget, laneEdgeTarget, supportDepthTarget]
        let best = bestScoredCandidate(subject: subject, candidates: candidates) { candidate in
            let bandScore = 1 - clamp(abs(candidate.y - midBandCenter) / 0.18, min: 0, max: 1)
            let laneScore = 1 - clamp(abs(candidate.x - laneCenterX) / 0.22, min: 0, max: 1)
            let movementScore = movementEconomyScore(subject: subject, target: candidate, idealDistance: 0.24)
            let depthScore = 1 - clamp(abs(candidate.y - 0.56) / 0.24, min: 0, max: 1)
            let edgeScore = edgeSafetyScore(for: candidate, margin: 0.14)
            return weightedScore([
                (bandScore, 0.24),
                (laneScore, 0.22),
                (movementScore, 0.18),
                (depthScore, 0.22),
                (edgeScore, 0.14)
            ])
        }
        let soft = weightedTarget(to: subject, in: [primaryTarget, centeredMidTarget, laneEdgeTarget], softness: 0.12)

        return CGPoint(
            x: clamp((best.x * 0.66) + (soft.x * 0.34), min: 0.14, max: 0.86),
            y: clamp((best.y * 0.66) + (soft.y * 0.34), min: 0.24, max: 0.78)
        )
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

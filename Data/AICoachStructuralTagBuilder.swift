import CoreGraphics
import Foundation

struct AICoachStructuralTagInput {
    let templateID: String?
    let subjectPoint: CGPoint?
    let targetPoint: CGPoint?
    let stableDx: CGFloat
    let stableDy: CGFloat
    let confidence: CGFloat
    let diagonalType: DiagonalType?
    let negativeSpaceZone: CGRect?
}

enum AICoachStructuralTagBuilder {
    static func build(input: AICoachStructuralTagInput) -> [String] {
        var tags: [String] = []

        let confidenceTag: String = {
            if input.confidence >= 0.72 { return "tracking-locked" }
            if input.confidence >= 0.35 { return "tracking-settling" }
            return "tracking-weak"
        }()
        tags.append(confidenceTag)

        let absX = abs(input.stableDx)
        let absY = abs(input.stableDy)
        if absX > 0.14 && absY > 0.14 {
            tags.append("drift-diagonal")
        } else if absX > absY + 0.04 {
            tags.append("drift-horizontal")
        } else if absY > absX + 0.04 {
            tags.append("drift-vertical")
        } else {
            tags.append("drift-balanced")
        }

        if let subjectPoint = input.subjectPoint, let targetPoint = input.targetPoint {
            let dx = targetPoint.x - subjectPoint.x
            let dy = targetPoint.y - subjectPoint.y
            if abs(dx) > 0.14 && abs(dy) > 0.14 {
                tags.append("target-shift-diagonal")
            } else if abs(dx) > abs(dy) + 0.05 {
                tags.append(dx > 0 ? "target-shift-right" : "target-shift-left")
            } else if abs(dy) > abs(dx) + 0.05 {
                tags.append(dy > 0 ? "target-shift-down" : "target-shift-up")
            } else {
                tags.append("target-near-lock")
            }
        }

        guard let templateID = input.templateID else {
            return Array(Set(tags)).sorted()
        }

        switch templateID {
        case "symmetry":
            if abs(input.stableDx) < 0.08 {
                tags.append("symmetry-axis-lock")
            } else {
                tags.append(input.stableDx > 0 ? "symmetry-axis-right" : "symmetry-axis-left")
            }
        case "leading_lines":
            if let targetPoint = input.targetPoint {
                let horizontal = targetPoint.x < 0.38 ? "vanish-left" : (targetPoint.x > 0.62 ? "vanish-right" : "vanish-center")
                let vertical = targetPoint.y < 0.40 ? "vanish-high" : "vanish-mid"
                tags.append(horizontal)
                tags.append(vertical)
            }
        case "rule_of_thirds":
            if let targetPoint = input.targetPoint {
                let firstThird: CGFloat = 1.0 / 3.0
                let secondThird: CGFloat = 2.0 / 3.0
                let nearVerticalThird = abs(targetPoint.x - firstThird) < 0.06 || abs(targetPoint.x - secondThird) < 0.06
                let nearHorizontalThird = abs(targetPoint.y - firstThird) < 0.06 || abs(targetPoint.y - secondThird) < 0.06
                if nearVerticalThird && nearHorizontalThird {
                    tags.append("thirds-intersection")
                } else if nearVerticalThird {
                    tags.append("thirds-vertical-line")
                } else if nearHorizontalThird {
                    tags.append("thirds-horizontal-line")
                }
            }
        case "golden_spiral":
            if let targetPoint = input.targetPoint {
                tags.append(targetPoint.x < 0.5 ? "spiral-left" : "spiral-right")
                tags.append(targetPoint.y < 0.5 ? "spiral-top" : "spiral-bottom")
            }
        case "diagonals":
            if let diagonalType = input.diagonalType {
                tags.append(diagonalType == .main ? "diagonal-main" : "diagonal-anti")
            } else {
                tags.append("diagonal-ambiguous")
            }
        case "negative_space":
            if let negativeSpaceZone = input.negativeSpaceZone {
                let horizontalSpace = negativeSpaceZone.width < negativeSpaceZone.height
                tags.append(horizontalSpace ? "space-horizontal" : "space-vertical")
                let zoneCenter = CGPoint(x: negativeSpaceZone.midX, y: negativeSpaceZone.midY)
                let horizontal = zoneCenter.x < 0.38 ? "space-left" : (zoneCenter.x > 0.62 ? "space-right" : "space-center")
                let vertical = zoneCenter.y < 0.38 ? "space-top" : (zoneCenter.y > 0.62 ? "space-bottom" : "space-mid")
                tags.append(horizontal)
                tags.append(vertical)
            }
        case "framing":
            if let targetPoint = input.targetPoint {
                let insideComfort = targetPoint.x >= 0.28 && targetPoint.x <= 0.72 && targetPoint.y >= 0.28 && targetPoint.y <= 0.72
                tags.append(insideComfort ? "frame-comfort" : "frame-recover")
            }
        case "portrait_headroom":
            if let targetPoint = input.targetPoint {
                tags.append(targetPoint.y < 0.42 ? "headroom-upper-band" : "headroom-mid-band")
                tags.append(abs(targetPoint.x - 0.5) < 0.08 ? "headroom-centered" : "headroom-side-balanced")
            }
        case "triangle":
            if let targetPoint = input.targetPoint {
                if targetPoint.y < 0.42 {
                    tags.append("triangle-apex")
                } else if targetPoint.y > 0.64 {
                    tags.append("triangle-base")
                } else {
                    tags.append(targetPoint.x < 0.5 ? "triangle-left-edge" : "triangle-right-edge")
                }
            }
        case "layers_fmb":
            if let targetPoint = input.targetPoint {
                tags.append("depth-mid-band")
                let lane = abs(targetPoint.x - 0.5) < 0.08 ? "depth-center-lane" : (targetPoint.x < 0.5 ? "depth-left-lane" : "depth-right-lane")
                tags.append(lane)
            }
        default:
            break
        }

        return Array(Set(tags)).sorted()
    }
}

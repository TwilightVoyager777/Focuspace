import Foundation
import SwiftUI

struct GuidanceDebugHUDView: View {
    var selectedTemplate: String?
    var guidanceUIMode: DebugSettings.GuidanceUIMode
    var rawDx: CGFloat
    var rawDy: CGFloat
    var rawStrength: CGFloat
    var rawConfidence: CGFloat
    var stableDx: CGFloat
    var stableDy: CGFloat
    var isHolding: Bool
    var subjectCurrentNormalized: CGPoint?
    var subjectTrackScore: Float
    var subjectIsLost: Bool

    private var templateName: String {
        selectedTemplate ?? "nil"
    }

    private var modeName: String {
        switch guidanceUIMode {
        case .moving:
            return "moving"
        case .arrow:
            return "arrow"
        }
    }

    private func fmt(_ value: CGFloat) -> String {
        String(format: "%.3f", value)
    }

    private func fmtPoint(_ point: CGPoint?) -> String {
        guard let point else {
            return "n/a"
        }
        return "(\(fmt(point.x)), \(fmt(point.y)))"
    }

    private func fmtSize(_ size: CGSize) -> String {
        "(\(fmt(size.width)), \(fmt(size.height)))"
    }

    var body: some View {
        let debugInfo = TemplateRuleEngine.debugInfo()
        let subject = subjectCurrentNormalized
        let sdx = (subject?.x ?? 0) - 0.5
        let sdy = (subject?.y ?? 0) - 0.5
        let sdist = sqrt(sdx * sdx + sdy * sdy)
        let gUi = CGSize(width: stableDx, height: stableDy)
        let dotOffsetPx = GuidanceUIConstants.clampedGuidanceOffset(gUi)
        let arrowStart = CGPoint(x: 0, y: 0)
        let arrowEnd = CGPoint(x: dotOffsetPx.width, y: dotOffsetPx.height)

        VStack(alignment: .leading, spacing: 4) {
            Text("template: \(templateName)")
            Text("templateType: \(debugInfo.templateType)")
            Text("mode: \(modeName)")
            if let subject {
                Text("subject: (\(fmt(subject.x)), \(fmt(subject.y)))")
                Text("subject→center dx: \(fmt(sdx)) dy: \(fmt(sdy))")
                Text("subject→center dist: \(fmt(sdist))")
            } else {
                Text("subject: lost")
            }
            Text("tracker score: \(String(format: "%.3f", subjectTrackScore))")
            Text("tracker lost: \(subjectIsLost ? "true" : "false")")
            Text("subjectPoint: \(fmtPoint(debugInfo.subjectPoint))")
            Text("subjectSource: \(debugInfo.subjectSource)")
            Text("target: \(fmtPoint(debugInfo.targetPoint))")
            Text("g_template: \(fmtSize(debugInfo.gTemplate))")
            Text("g_stable: \(fmtSize(CGSize(width: stableDx, height: stableDy)))")
            Text("g_ui: \(fmtSize(gUi))")
            if guidanceUIMode == .arrow {
                Text("arrowStart(px): (\(fmt(arrowStart.x)), \(fmt(arrowStart.y)))")
                Text("arrowEnd(px): (\(fmt(arrowEnd.x)), \(fmt(arrowEnd.y)))")
                Text("dotPx: \(fmtSize(dotOffsetPx))")
            }
            Text("holding: \(isHolding ? "true" : "false")")
            Text("errMag: \(fmt(debugInfo.errMag))")
        }
        .font(.system(size: 12, weight: .regular, design: .monospaced))
        .foregroundColor(.white)
        .padding(8)
        .background(.black.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private enum GuidanceQuadrant: String {
    case upLeft = "upLeft"
    case upRight = "upRight"
    case downLeft = "downLeft"
    case downRight = "downRight"
    case up = "up"
    case down = "down"
    case left = "left"
    case right = "right"
    case center = "center"
}

private struct GuidanceSelfTestCase {
    let name: String
    let subject: CGPoint
    let expectedQuadrant: GuidanceQuadrant
}

private func quadrant(for offset: CGSize, epsilon: CGFloat = 0.001) -> GuidanceQuadrant {
    let dx = offset.width
    let dy = offset.height
    let absDx = abs(dx)
    let absDy = abs(dy)
    if absDx < epsilon && absDy < epsilon {
        return .center
    }
    if absDx < epsilon {
        return dy < 0 ? .up : .down
    }
    if absDy < epsilon {
        return dx < 0 ? .left : .right
    }
    if dx < 0 && dy < 0 {
        return .upLeft
    }
    if dx > 0 && dy < 0 {
        return .upRight
    }
    if dx < 0 && dy > 0 {
        return .downLeft
    }
    return .downRight
}

struct GuidanceSelfTestView: View {
    private let cases: [GuidanceSelfTestCase] = [
        GuidanceSelfTestCase(
            name: "diag upLeft",
            subject: CGPoint(x: 0.2, y: 0.2),
            expectedQuadrant: .upLeft
        ),
        GuidanceSelfTestCase(
            name: "right",
            subject: CGPoint(x: 0.7, y: 0.5),
            expectedQuadrant: .right
        ),
        GuidanceSelfTestCase(
            name: "left",
            subject: CGPoint(x: 0.3, y: 0.5),
            expectedQuadrant: .left
        ),
        GuidanceSelfTestCase(
            name: "down",
            subject: CGPoint(x: 0.5, y: 0.7),
            expectedQuadrant: .down
        ),
        GuidanceSelfTestCase(
            name: "up",
            subject: CGPoint(x: 0.5, y: 0.3),
            expectedQuadrant: .up
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Guidance Self-Test")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)

            ForEach(Array(cases.enumerated()), id: \.offset) { _, test in
                let subjectOffset = CGSize(
                    width: test.subject.x - 0.5,
                    height: test.subject.y - 0.5
                )
                let dotPx = GuidanceUIConstants.clampedGuidanceOffset(subjectOffset)
                let actual = quadrant(for: dotPx)
                let pass = actual == test.expectedQuadrant
                let strength = min(1, sqrt(subjectOffset.width * subjectOffset.width + subjectOffset.height * subjectOffset.height))

                HStack(spacing: 12) {
                    ArrowGuidanceHUDView(
                        guidanceOffset: subjectOffset,
                        strength: strength,
                        isHolding: false
                    )
                    .frame(width: 120, height: 120)
                    .background(Color.black.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(test.name)
                        Text("expected: \(test.expectedQuadrant.rawValue)")
                        Text("actual: \(actual.rawValue)")
                        Text(pass ? "PASS" : "FAIL")
                            .foregroundColor(pass ? .green : .red)
                    }
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(.white)
                }
            }
        }
        .padding(12)
        .background(Color.black)
    }
}

struct GuidanceSelfTestView_Previews: PreviewProvider {
    static var previews: some View {
        GuidanceSelfTestView()
            .previewLayout(.sizeThatFits)
    }
}

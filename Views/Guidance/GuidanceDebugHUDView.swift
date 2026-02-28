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
    var effectiveAnchorNormalized: CGPoint
    var userAnchorNormalized: CGPoint?
    var autoFocusAnchorNormalized: CGPoint
    var uiDx: CGFloat?
    var uiDy: CGFloat?

    private var templateName: String {
        selectedTemplate ?? "None"
    }

    private var modeName: String {
        switch guidanceUIMode {
        case .moving:
            return "Moving Dot"
        case .arrow:
            return "Arrow"
        case .arrowScope:
            return "Arrow (Scope)"
        }
    }

    private func fmt(_ value: CGFloat) -> String {
        String(format: "%.3f", value)
    }

    private func fmtPoint(_ point: CGPoint?) -> String {
        guard let point else {
            return "None"
        }
        return "(\(fmt(point.x)), \(fmt(point.y)))"
    }

    private func fmtSize(_ size: CGSize) -> String {
        "(\(fmt(size.width)), \(fmt(size.height)))"
    }

    private func boolText(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }

    private func sign(_ value: CGFloat, epsilon: CGFloat = 0.0001) -> Int {
        if value > epsilon { return 1 }
        if value < -epsilon { return -1 }
        return 0
    }

    var body: some View {
        let debugInfo = TemplateRuleEngine.debugInfo()
        let subject = subjectCurrentNormalized
        let gUi = CGSize(
            width: uiDx ?? -stableDx,
            height: uiDy ?? -stableDy
        )
        let dotOffsetPx = GuidanceUIConstants.clampedGuidanceOffset(gUi)
        let arrowEnd = CGPoint(x: dotOffsetPx.width, y: dotOffsetPx.height)
        let tapVisionDistance: CGFloat? = {
            guard let userAnchor = userAnchorNormalized, let subject else { return nil }
            let dx = subject.x - userAnchor.x
            let dy = subject.y - userAnchor.y
            return sqrt(dx * dx + dy * dy)
        }()
        let anchorMode = userAnchorNormalized == nil ? "Auto Anchor" : "Tap Anchor"
        let subjectX = debugInfo.subjectPoint?.x
        let targetX = debugInfo.targetPoint?.x
        let xCheckText: String = {
            guard let subjectX, let targetX else { return "X Check: No Data" }
            let expectedTemplateDx = targetX - subjectX
            let expectedTemplateSign = sign(expectedTemplateDx)
            let actualTemplateSign = sign(debugInfo.gTemplate.width)
            let actualUiSign = sign(gUi.width)
            let passTemplate = expectedTemplateSign == 0 || actualTemplateSign == expectedTemplateSign
            let passUi = expectedTemplateSign == 0 || actualUiSign == -expectedTemplateSign
            let pass = passTemplate && passUi
            let side = subjectX >= 0.5 ? "Subject on Right (x>=0.5)" : "Subject on Left (x<0.5)"
            return "X Check: \(pass ? "Pass" : "Fail") | \(side)"
        }()

        VStack(alignment: .leading, spacing: 4) {
            Text("Template ID: \(templateName)")
            Text("Template Type: \(debugInfo.templateType)")
            Text("Guidance Mode: \(modeName)")
            if let subject {
                Text("Subject Position: (\(fmt(subject.x)), \(fmt(subject.y)))")
                // Text("主体到中心偏移: ...")
                // Text("主体到中心距离: ...")
            } else {
                Text("Subject Status: Lost")
            }
            Text("Tracking Confidence: \(String(format: "%.3f", subjectTrackScore))")
            Text("Tracking Lost: \(boolText(subjectIsLost))")
            Text("Anchor Mode: \(anchorMode)")
            Text("Auto Anchor: \(fmtPoint(autoFocusAnchorNormalized))")
            Text("Tap Anchor: \(fmtPoint(userAnchorNormalized))")
            Text("Effective Anchor: \(fmtPoint(effectiveAnchorNormalized))")
            if let tapVisionDistance {
                Text("Tap to Track Distance: \(fmt(tapVisionDistance))")
            }
            Text("Rule Input Subject: \(fmtPoint(debugInfo.subjectPoint))")
            Text("Subject Source: \(debugInfo.subjectSource)")
            Text("Target Point: \(fmtPoint(debugInfo.targetPoint))")
            Text("Template Vector g_template: \(fmtSize(debugInfo.gTemplate))")
            // Text("原始向量 raw(dx,dy): (\(fmt(rawDx)), \(fmt(rawDy)))")
            // Text("原始强度 rawStrength: \(fmt(rawStrength))")
            // Text("原始置信度 rawConfidence: \(fmt(rawConfidence))")
            // Text("稳定后向量 g_stable: \(fmtSize(CGSize(width: stableDx, height: stableDy)))")
            Text("UI Vector g_ui: \(fmtSize(gUi))")
            Text(xCheckText)
            if guidanceUIMode == .arrow || guidanceUIMode == .arrowScope {
                // Text("箭头起点(px): ...")
                Text("Arrow End (px): (\(fmt(arrowEnd.x)), \(fmt(arrowEnd.y)))")
                Text("Dot Offset (px): \(fmtSize(dotOffsetPx))")
            }
            Text("Holding: \(boolText(isHolding))")
            // Text("误差幅值 errMag: \(fmt(debugInfo.errMag))")
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

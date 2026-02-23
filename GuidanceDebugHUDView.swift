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

    var body: some View {
        let subject = subjectCurrentNormalized
        let sdx = (subject?.x ?? 0) - 0.5
        let sdy = (subject?.y ?? 0) - 0.5
        let sdist = sqrt(sdx * sdx + sdy * sdy)

        VStack(alignment: .leading, spacing: 4) {
            Text("template: \(templateName)")
            Text("mode: \(modeName)")
            if let subject {
                Text("subject: (\(fmt(subject.x)), \(fmt(subject.y)))")
                Text("subject→center dx: \(fmt(sdx)) dy: \(fmt(sdy))")
                Text("subject→center dist: \(fmt(sdist))")
            } else {
                Text("subject: lost")
            }
            Text("subject score: \(String(format: "%.3f", subjectTrackScore))")
            Text("raw: dx \(fmt(rawDx)) dy \(fmt(rawDy))")
            Text("raw: strength \(fmt(rawStrength)) conf \(fmt(rawConfidence))")
            Text("stable: dx \(fmt(stableDx)) dy \(fmt(stableDy))")
            Text("holding: \(isHolding ? "true" : "false")")
        }
        .font(.system(size: 12, weight: .regular, design: .monospaced))
        .foregroundColor(.white)
        .padding(8)
        .background(.black.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

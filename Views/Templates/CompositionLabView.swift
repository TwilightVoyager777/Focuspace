import SwiftUI

struct CompositionTemplate: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let philosophy: String
    let exampleImages: [String]
}

struct CompositionLabView: View {
    let selectTemplate: (String) -> Void

    private let templates: [CompositionTemplate] = CompositionTemplate.mock
    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(templates) { template in
                    NavigationLink {
                        TemplateDetailView(template: template, selectTemplate: selectTemplate)
                    } label: {
                        TemplateCardView(template: template)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Composition Lab")
        .navigationBarTitleDisplayMode(.large)
    }
}

struct TemplateCardView: View {
    let template: CompositionTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ExamplePlaceholderView(
                label: template.name,
                cornerRadius: 12,
                height: 180
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)

                Text(template.subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(Color(white: 0.07))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
    }
}

struct TemplateDetailView: View {
    let template: CompositionTemplate
    let selectTemplate: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private let galleryColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroSection

                VStack(alignment: .leading, spacing: 12) {
                    Text("Examples")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)

                    LazyVGrid(columns: galleryColumns, spacing: 8) {
                        ForEach(template.exampleImages.indices, id: \.self) { index in
                            ExamplePlaceholderView(
                                label: template.exampleImages[index],
                                cornerRadius: 8,
                                height: galleryHeight(for: index)
                            )
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("How To Use")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)

                    ForEach(bullets(for: template.id), id: \.self) { bullet in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .foregroundColor(.white.opacity(0.85))
                            Text(bullet)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.white.opacity(0.75))
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Composition Lab")
        .navigationBarTitleDisplayMode(.large)
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(template.name)
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.white)

            Text(template.philosophy)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.white.opacity(0.7))

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
                    .background(Color(white: 0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                CompositionDiagramView(templateID: template.id)
                    .stroke(Color.white.opacity(0.8), lineWidth: 1.2)
                    .padding(24)
            }
            .frame(height: 180)

            Button {
                selectTemplate(template.id)
                dismiss()
            } label: {
                Text("Start Shooting")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func bullets(for id: String) -> [String] {
        switch id {
        case "rule_of_thirds":
            return [
                "Place the subject near intersecting thirds.",
                "Align horizon on upper or lower third.",
                "Avoid centering unless intentional."
            ]
        case "golden_spiral":
            return [
                "Guide the eye along the spiral curve.",
                "Position the focal point at the spiral core.",
                "Keep the flow unobstructed."
            ]
        case "center":
            return [
                "Use strong symmetry for impact.",
                "Keep edges clean and balanced.",
                "Let the subject dominate the frame."
            ]
        case "symmetry":
            return [
                "Find mirrored shapes or reflections.",
                "Keep the center line precise.",
                "Reduce distractions at the edges."
            ]
        case "leading_lines":
            return [
                "Use lines to direct attention.",
                "Keep lines clean and intentional.",
                "Let lines converge on the subject."
            ]
        case "framing":
            return [
                "Use foreground elements as a frame.",
                "Keep the subject inside the window.",
                "Balance frame weight on both sides."
            ]
        default:
            return [
                "Give the subject room to breathe.",
                "Use emptiness to emphasize form.",
                "Simplify the background."
            ]
        }
    }

    private func galleryHeight(for index: Int) -> CGFloat {
        let heights: [CGFloat] = [140, 180, 160, 200, 150, 190]
        return heights[index % heights.count]
    }
}

struct CompositionDiagramView: Shape {
    let templateID: String

    func path(in rect: CGRect) -> Path {
        switch templateID {
        case "rule_of_thirds":
            return thirdsPath(in: rect)
        case "golden_spiral":
            return spiralPath(in: rect)
        case "center":
            return centerPath(in: rect)
        case "symmetry":
            return symmetryPath(in: rect)
        case "leading_lines":
            return leadingLinesPath(in: rect)
        case "framing":
            return framingPath(in: rect)
        default:
            return negativeSpacePath(in: rect)
        }
    }

    private func thirdsPath(in rect: CGRect) -> Path {
        var path = Path()
        let thirdW = rect.width / 3
        let thirdH = rect.height / 3
        path.move(to: CGPoint(x: thirdW, y: rect.minY))
        path.addLine(to: CGPoint(x: thirdW, y: rect.maxY))
        path.move(to: CGPoint(x: thirdW * 2, y: rect.minY))
        path.addLine(to: CGPoint(x: thirdW * 2, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: thirdH))
        path.addLine(to: CGPoint(x: rect.maxX, y: thirdH))
        path.move(to: CGPoint(x: rect.minX, y: thirdH * 2))
        path.addLine(to: CGPoint(x: rect.maxX, y: thirdH * 2))
        return path
    }

    private func spiralPath(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let maxRadius = min(rect.width, rect.height) / 2
        let turns: CGFloat = 2.2
        let steps = 64
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let angle = t * turns * 2 * .pi
            let radius = maxRadius * t
            let point = CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }

    private func centerPath(in rect: CGRect) -> Path {
        var path = Path()
        let circleRect = rect.insetBy(dx: rect.width * 0.25, dy: rect.height * 0.25)
        path.addEllipse(in: circleRect)
        return path
    }

    private func symmetryPath(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }

    private func leadingLinesPath(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }

    private func framingPath(in rect: CGRect) -> Path {
        var path = Path()
        let insetRect = rect.insetBy(dx: rect.width * 0.15, dy: rect.height * 0.15)
        path.addRect(insetRect)
        return path
    }

    private func negativeSpacePath(in rect: CGRect) -> Path {
        var path = Path()
        let smallRect = CGRect(
            x: rect.minX + rect.width * 0.6,
            y: rect.minY + rect.height * 0.2,
            width: rect.width * 0.25,
            height: rect.height * 0.25
        )
        path.addRect(smallRect)
        return path
    }
}

struct ExamplePlaceholderView: View {
    let label: String
    let cornerRadius: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(white: 0.2), Color(white: 0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension CompositionTemplate {
    static let mock: [CompositionTemplate] = [
        CompositionTemplate(
            id: "rule_of_thirds",
            name: "Rule of Thirds",
            subtitle: "Balance and dynamic tension",
            philosophy: "Let the subject breathe within the frame.",
            exampleImages: ["Thirds 01", "Thirds 02", "Thirds 03", "Thirds 04"]
        ),
        CompositionTemplate(
            id: "golden_spiral",
            name: "Golden Spiral",
            subtitle: "Natural visual flow",
            philosophy: "Guide attention along a quiet curve.",
            exampleImages: ["Spiral 01", "Spiral 02", "Spiral 03", "Spiral 04"]
        ),
        CompositionTemplate(
            id: "center",
            name: "Center Composition",
            subtitle: "Intentional symmetry",
            philosophy: "Centering creates calm, confident focus.",
            exampleImages: ["Center 01", "Center 02", "Center 03"]
        ),
        CompositionTemplate(
            id: "symmetry",
            name: "Symmetry",
            subtitle: "Reflections and balance",
            philosophy: "Mirror the scene for a refined order.",
            exampleImages: ["Symmetry 01", "Symmetry 02", "Symmetry 03"]
        ),
        CompositionTemplate(
            id: "leading_lines",
            name: "Leading Lines",
            subtitle: "Direct the viewer",
            philosophy: "Use lines to draw focus with intent.",
            exampleImages: ["Lines 01", "Lines 02", "Lines 03", "Lines 04"]
        ),
        CompositionTemplate(
            id: "framing",
            name: "Framing",
            subtitle: "Layers and depth",
            philosophy: "Build a visual window for the subject.",
            exampleImages: ["Frame 01", "Frame 02", "Frame 03"]
        ),
        CompositionTemplate(
            id: "negative_space",
            name: "Negative Space",
            subtitle: "Minimal emphasis",
            philosophy: "Let emptiness amplify the subject.",
            exampleImages: ["Space 01", "Space 02", "Space 03"]
        )
    ]
}

import CoreGraphics

struct TemplateOverlayEngine {
    func primitives(for model: TemplateOverlayModel) -> [OverlayPrimitive] {
        var primitives: [OverlayPrimitive] = []

        if model.templateId == "negative_space",
           let rect = model.negativeSpaceZone {
            primitives.append(.rectBox(RectBox(rect: rect, cornerRadius: 0.02, dashed: false, opacity: 0.75)))
        }

        if model.templateId == "diagonals",
           let diagonalType = model.diagonalType {
            let line: Line
            switch diagonalType {
            case .main:
                line = Line(from: CGPoint(x: 0.0, y: 0.0), to: CGPoint(x: 1.0, y: 1.0), opacity: 0.9)
            case .anti:
                line = Line(from: CGPoint(x: 0.0, y: 1.0), to: CGPoint(x: 1.0, y: 0.0), opacity: 0.9)
            }
            primitives.append(.line(line))
        }

        if let target = model.targetPoint {
            primitives.append(.dot(Dot(at: target, radius: 0.012, opacity: 1.0)))
        }

        return primitives
    }
}

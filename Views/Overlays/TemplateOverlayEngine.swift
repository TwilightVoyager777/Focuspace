import CoreGraphics

struct TemplateOverlayEngine {
    func primitives(for model: TemplateOverlayModel) -> [OverlayPrimitive] {
        switch model.templateId {
        case "rule_of_thirds":
            return thirdsPrimitives(model: model)
        case "golden_spiral":
            return goldenSpiralPrimitives(model: model)
        case "center":
            return centerPrimitives(model: model)
        case "symmetry":
            return symmetryPrimitives()
        case "leading_lines":
            return leadingLinesPrimitives(model: model)
        case "framing":
            return framingPrimitives()
        case "negative_space":
            return negativeSpacePrimitives(model: model)
        case "portrait_headroom":
            return portraitHeadroomPrimitives()
        case "diagonals":
            return diagonalsPrimitives(model: model)
        case "triangle":
            return trianglePrimitives()
        case "layers_fmb":
            return layersPrimitives()
        default:
            return []
        }
    }

    private func thirdsPrimitives(model: TemplateOverlayModel) -> [OverlayPrimitive] {
        let points = [
            CGPoint(x: 1.0 / 3.0, y: 1.0 / 3.0),
            CGPoint(x: 2.0 / 3.0, y: 1.0 / 3.0),
            CGPoint(x: 1.0 / 3.0, y: 2.0 / 3.0),
            CGPoint(x: 2.0 / 3.0, y: 2.0 / 3.0)
        ]
        var primitives: [OverlayPrimitive] = [
            .line(Line(from: CGPoint(x: 1.0 / 3.0, y: 0.0), to: CGPoint(x: 1.0 / 3.0, y: 1.0), opacity: 0.35)),
            .line(Line(from: CGPoint(x: 2.0 / 3.0, y: 0.0), to: CGPoint(x: 2.0 / 3.0, y: 1.0), opacity: 0.35)),
            .line(Line(from: CGPoint(x: 0.0, y: 1.0 / 3.0), to: CGPoint(x: 1.0, y: 1.0 / 3.0), opacity: 0.35)),
            .line(Line(from: CGPoint(x: 0.0, y: 2.0 / 3.0), to: CGPoint(x: 1.0, y: 2.0 / 3.0), opacity: 0.35))
        ]
        primitives.append(contentsOf: points.map { .dot(Dot(at: $0, radius: 0.007, opacity: 0.8)) })
        if let target = model.targetPoint {
            primitives.append(.dot(Dot(at: target, radius: 0.012, opacity: 1.0)))
        }
        return primitives
    }

    private func goldenSpiralPrimitives(model: TemplateOverlayModel) -> [OverlayPrimitive] {
        let a: CGFloat = 0.382
        let b: CGFloat = 0.618
        let points = [
            CGPoint(x: a, y: a),
            CGPoint(x: b, y: a),
            CGPoint(x: a, y: b),
            CGPoint(x: b, y: b)
        ]
        var primitives: [OverlayPrimitive] = [
            .line(Line(from: CGPoint(x: a, y: 0.0), to: CGPoint(x: a, y: 1.0), opacity: 0.25)),
            .line(Line(from: CGPoint(x: b, y: 0.0), to: CGPoint(x: b, y: 1.0), opacity: 0.25)),
            .line(Line(from: CGPoint(x: 0.0, y: a), to: CGPoint(x: 1.0, y: a), opacity: 0.25)),
            .line(Line(from: CGPoint(x: 0.0, y: b), to: CGPoint(x: 1.0, y: b), opacity: 0.25))
        ]
        primitives.append(contentsOf: points.map { .dot(Dot(at: $0, radius: 0.007, opacity: 0.85)) })
        if let target = model.targetPoint {
            primitives.append(.dot(Dot(at: target, radius: 0.012, opacity: 1.0)))
        }
        return primitives
    }

    private func centerPrimitives(model: TemplateOverlayModel) -> [OverlayPrimitive] {
        guard model.strength > 0 else { return [] }
        return [
            .dot(Dot(at: CGPoint(x: 0.5, y: 0.5), radius: 0.01, opacity: 0.5))
        ]
    }

    private func symmetryPrimitives() -> [OverlayPrimitive] {
        [
            .line(Line(from: CGPoint(x: 0.5, y: 0.0), to: CGPoint(x: 0.5, y: 1.0), opacity: 0.7))
        ]
    }

    private func leadingLinesPrimitives(model: TemplateOverlayModel) -> [OverlayPrimitive] {
        let vanishing = model.targetPoint ?? CGPoint(x: 0.5, y: 0.45)
        return [
            .line(Line(from: CGPoint(x: 0.15, y: 1.0), to: vanishing, opacity: 0.45)),
            .line(Line(from: CGPoint(x: 0.85, y: 1.0), to: vanishing, opacity: 0.45))
        ]
    }

    private func framingPrimitives() -> [OverlayPrimitive] {
        let rect = CGRect(x: 0.12, y: 0.12, width: 0.76, height: 0.76)
        return [
            .rectBox(RectBox(rect: rect, cornerRadius: 0.04, dashed: false, opacity: 0.6))
        ]
    }

    private func negativeSpacePrimitives(model: TemplateOverlayModel) -> [OverlayPrimitive] {
        var primitives: [OverlayPrimitive] = []
        if let rect = model.negativeSpaceZone {
            primitives.append(.rectBox(RectBox(rect: rect, cornerRadius: 0.02, dashed: false, opacity: 0.6)))
        }
        if let target = model.targetPoint {
            primitives.append(.dot(Dot(at: target, radius: 0.012, opacity: 1.0)))
        }
        return primitives
    }

    private func portraitHeadroomPrimitives() -> [OverlayPrimitive] {
        [
            .line(Line(from: CGPoint(x: 0.0, y: 0.40), to: CGPoint(x: 1.0, y: 0.40), opacity: 0.55)),
            .line(Line(from: CGPoint(x: 0.0, y: 0.15), to: CGPoint(x: 1.0, y: 0.15), opacity: 0.25))
        ]
    }

    private func diagonalsPrimitives(model: TemplateOverlayModel) -> [OverlayPrimitive] {
        let isAnti = model.diagonalKind == 1
        if isAnti {
            return [
                .line(Line(from: CGPoint(x: 0.0, y: 1.0), to: CGPoint(x: 1.0, y: 0.0), opacity: 0.6))
            ]
        }
        return [
            .line(Line(from: CGPoint(x: 0.0, y: 0.0), to: CGPoint(x: 1.0, y: 1.0), opacity: 0.6))
        ]
    }

    private func trianglePrimitives() -> [OverlayPrimitive] {
        let points = [
            CGPoint(x: 0.5, y: 0.18),
            CGPoint(x: 0.20, y: 0.82),
            CGPoint(x: 0.80, y: 0.82),
            CGPoint(x: 0.5, y: 0.18)
        ]
        return [
            .path(PathOverlay(points: points, opacity: 0.6))
        ]
    }

    private func layersPrimitives() -> [OverlayPrimitive] {
        [
            .line(Line(from: CGPoint(x: 0.0, y: 0.33), to: CGPoint(x: 1.0, y: 0.33), opacity: 0.4)),
            .line(Line(from: CGPoint(x: 0.0, y: 0.66), to: CGPoint(x: 1.0, y: 0.66), opacity: 0.4))
        ]
    }
}

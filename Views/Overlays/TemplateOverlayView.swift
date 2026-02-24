import SwiftUI

struct TemplateOverlayView: View {
    let model: TemplateOverlayModel

    private let engine = TemplateOverlayEngine()

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let baseAlpha = clamp(0.15 + 0.6 * model.strength, min: 0.15, max: 0.55)
            let primitives = engine.primitives(for: model)

            ZStack {
                ForEach(Array(primitives.enumerated()), id: \.offset) { _, primitive in
                    primitiveView(primitive, size: size, baseAlpha: baseAlpha)
                }
            }
        }
    }

    private func primitiveView(_ primitive: OverlayPrimitive, size: CGSize, baseAlpha: CGFloat) -> some View {
        switch primitive {
        case .line(let line):
            return AnyView(
                Path { path in
                    path.move(to: point(line.from, in: size))
                    path.addLine(to: point(line.to, in: size))
                }
                .stroke(Color.white.opacity(baseAlpha * line.opacity), lineWidth: 1)
            )
        case .dot(let dot):
            let radius = min(size.width, size.height) * dot.radius
            return AnyView(
                Circle()
                    .fill(Color.white.opacity(baseAlpha * dot.opacity))
                    .frame(width: radius * 2, height: radius * 2)
                    .position(point(dot.at, in: size))
            )
        case .rectBox(let box):
            let rect = CGRect(
                x: box.rect.minX * size.width,
                y: box.rect.minY * size.height,
                width: box.rect.width * size.width,
                height: box.rect.height * size.height
            )
            let radius = min(size.width, size.height) * box.cornerRadius
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            let strokeStyle = StrokeStyle(lineWidth: 1, dash: box.dashed ? [4, 4] : [])
            return AnyView(
                shape
                    .path(in: rect)
                    .stroke(Color.white.opacity(baseAlpha * box.opacity), style: strokeStyle)
            )
        case .band(let band):
            let rect = CGRect(
                x: 0,
                y: band.yRange.lowerBound * size.height,
                width: size.width,
                height: (band.yRange.upperBound - band.yRange.lowerBound) * size.height
            )
            return AnyView(
                Rectangle()
                    .path(in: rect)
                    .stroke(Color.white.opacity(baseAlpha * band.opacity), lineWidth: 1)
            )
        case .path(let pathOverlay):
            return AnyView(
                Path { path in
                    guard let first = pathOverlay.points.first else { return }
                    path.move(to: point(first, in: size))
                    for p in pathOverlay.points.dropFirst() {
                        path.addLine(to: point(p, in: size))
                    }
                }
                .stroke(Color.white.opacity(baseAlpha * pathOverlay.opacity), lineWidth: 1)
            )
        }
    }

    private func point(_ p: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: p.x * size.width, y: p.y * size.height)
    }

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(value, max))
    }
}

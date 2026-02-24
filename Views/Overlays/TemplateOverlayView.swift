import SwiftUI

struct TemplateOverlayView: View {
    let model: TemplateOverlayModel

    private var alpha: CGFloat {
        min(0.55, 0.15 + model.strength * 0.6)
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let color = Color.white.opacity(alpha)
            let highlight = Color.white.opacity(min(0.85, alpha + 0.25))

            ZStack {
                switch model.template {
                case .symmetry:
                    Path { path in
                        let x = size.width * 0.5
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    .stroke(color, lineWidth: 1)
                case .center:
                    Circle()
                        .stroke(color, lineWidth: 1)
                        .frame(width: 12, height: 12)
                        .position(point(model.targetPoint, in: size))
                case .thirds:
                    thirdsGrid(size: size, color: color)
                    let points = thirdsPoints()
                    ForEach(points.indices, id: \.self) { index in
                        Circle()
                            .fill(color)
                            .frame(width: 3, height: 3)
                            .position(point(points[index], in: size))
                    }
                    Circle()
                        .fill(highlight)
                        .frame(width: 6, height: 6)
                        .position(point(model.targetPoint, in: size))
                case .goldenPoints:
                    let points = goldenPoints()
                    ForEach(points.indices, id: \.self) { index in
                        Circle()
                            .fill(color)
                            .frame(width: 3, height: 3)
                            .position(point(points[index], in: size))
                    }
                    Circle()
                        .fill(highlight)
                        .frame(width: 6, height: 6)
                        .position(point(model.targetPoint, in: size))
                case .diagonal:
                    Path { path in
                        switch model.selectedDiagonal ?? .main {
                        case .main:
                            path.move(to: CGPoint(x: 0, y: 0))
                            path.addLine(to: CGPoint(x: size.width, y: size.height))
                        case .anti:
                            path.move(to: CGPoint(x: 0, y: size.height))
                            path.addLine(to: CGPoint(x: size.width, y: 0))
                        }
                    }
                    .stroke(color, lineWidth: 1)
                    Circle()
                        .fill(highlight)
                        .frame(width: 5, height: 5)
                        .position(point(model.targetPoint, in: size))
                case .negativeSpace:
                    if let rect = model.negativeSpaceZone {
                        Rectangle()
                            .stroke(color, lineWidth: 1)
                            .frame(width: rect.width * size.width, height: rect.height * size.height)
                            .position(rectCenter(rect, in: size))
                        Circle()
                            .fill(highlight)
                            .frame(width: 5, height: 5)
                            .position(point(model.targetPoint, in: size))
                    }
                case .other:
                    EmptyView()
                }
            }
        }
    }

    private func point(_ p: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: p.x * size.width, y: p.y * size.height)
    }

    private func rectCenter(_ rect: CGRect, in size: CGSize) -> CGPoint {
        CGPoint(
            x: (rect.minX + rect.width * 0.5) * size.width,
            y: (rect.minY + rect.height * 0.5) * size.height
        )
    }

    private func thirdsGrid(size: CGSize, color: Color) -> some View {
        let x1 = size.width / 3.0
        let x2 = x1 * 2.0
        let y1 = size.height / 3.0
        let y2 = y1 * 2.0
        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: x1, y: 0))
                path.addLine(to: CGPoint(x: x1, y: size.height))
                path.move(to: CGPoint(x: x2, y: 0))
                path.addLine(to: CGPoint(x: x2, y: size.height))
                path.move(to: CGPoint(x: 0, y: y1))
                path.addLine(to: CGPoint(x: size.width, y: y1))
                path.move(to: CGPoint(x: 0, y: y2))
                path.addLine(to: CGPoint(x: size.width, y: y2))
            }
            .stroke(color, lineWidth: 1)
        }
    }

    private func thirdsPoints() -> [CGPoint] {
        [
            CGPoint(x: 1.0 / 3.0, y: 1.0 / 3.0),
            CGPoint(x: 2.0 / 3.0, y: 1.0 / 3.0),
            CGPoint(x: 1.0 / 3.0, y: 2.0 / 3.0),
            CGPoint(x: 2.0 / 3.0, y: 2.0 / 3.0)
        ]
    }

    private func goldenPoints() -> [CGPoint] {
        let a: CGFloat = 0.382
        let b: CGFloat = 0.618
        return [
            CGPoint(x: a, y: a),
            CGPoint(x: b, y: a),
            CGPoint(x: a, y: b),
            CGPoint(x: b, y: b)
        ]
    }
}

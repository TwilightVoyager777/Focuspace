import SwiftUI

struct TemplateOverlayView: View {
    let model: TemplateOverlayModel

    private let engine = TemplateOverlayEngine()

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let baseAlpha = clamp(0.15 + 0.6 * model.strength, min: 0.15, max: 0.55)
            let shouldRenderLegacyPrimitives =
                model.diagonalType != nil || model.negativeSpaceZone != nil

            ZStack {
                TemplateOverlayDiagramShape(templateID: model.templateId)
                    .stroke(Color.white.opacity(baseAlpha * 0.7), lineWidth: 1)

                if shouldRenderLegacyPrimitives {
                    let primitives = engine.primitives(for: model)
                    ForEach(Array(primitives.enumerated()), id: \.offset) { _, primitive in
                        primitiveView(primitive, size: size, baseAlpha: baseAlpha)
                    }
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

private struct TemplateOverlayDiagramShape: Shape {
    let templateID: String

    func path(in rect: CGRect) -> Path {
        let inset = min(rect.width, rect.height) * 0.08
        let r = rect.insetBy(dx: inset, dy: inset)
        var path = Path()
        path.addPath(borderPath(in: r))

        switch templateID {
        case "rule_of_thirds":
            path.addPath(thirdsPath(in: r))
        case "golden_spiral":
            path.addPath(goldenSpiralPath(in: r))
        case "center":
            path.addPath(centerPath(in: r))
        case "symmetry":
            path.addPath(symmetryPath(in: r))
        case "leading_lines":
            path.addPath(leadingLinesPath(in: r))
        case "framing":
            path.addPath(framingPath(in: r))
        case "portrait_headroom":
            path.addPath(portraitHeadroomPath(in: r))
        case "diagonals":
            path.addPath(diagonalsPath(in: r))
        case "triangle":
            path.addPath(trianglePath(in: r))
        case "layers_fmb":
            path.addPath(layersFMBPath(in: r))
        default:
            path.addPath(negativeSpacePath(in: r))
        }

        return path
    }

    private func borderPath(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) * 0.06
        var path = Path()
        path.addRoundedRect(in: rect, cornerSize: CGSize(width: radius, height: radius))
        return path
    }

    private func thirdsPath(in rect: CGRect) -> Path {
        var path = Path()
        let thirdW = rect.width / 3
        let thirdH = rect.height / 3
        let x1 = rect.minX + thirdW
        let x2 = rect.minX + thirdW * 2
        let y1 = rect.minY + thirdH
        let y2 = rect.minY + thirdH * 2

        path.move(to: CGPoint(x: x1, y: rect.minY))
        path.addLine(to: CGPoint(x: x1, y: rect.maxY))
        path.move(to: CGPoint(x: x2, y: rect.minY))
        path.addLine(to: CGPoint(x: x2, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: y1))
        path.addLine(to: CGPoint(x: rect.maxX, y: y1))
        path.move(to: CGPoint(x: rect.minX, y: y2))
        path.addLine(to: CGPoint(x: rect.maxX, y: y2))

        let dotRadius = min(rect.width, rect.height) * 0.02
        let dots = [
            CGPoint(x: x1, y: y1),
            CGPoint(x: x2, y: y1),
            CGPoint(x: x1, y: y2),
            CGPoint(x: x2, y: y2)
        ]
        for dot in dots {
            let dotRect = CGRect(
                x: dot.x - dotRadius,
                y: dot.y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )
            path.addEllipse(in: dotRect)
        }

        let centerRadius = dotRadius * 0.45
        let centerRect = CGRect(
            x: rect.midX - centerRadius,
            y: rect.midY - centerRadius,
            width: centerRadius * 2,
            height: centerRadius * 2
        )
        path.addEllipse(in: centerRect)
        return path
    }

    private func goldenSpiralPath(in rect: CGRect) -> Path {
        var path = Path()
        let maxIterations = 7
        var remaining = rect
        var direction = remaining.width >= remaining.height ? 0 : 1

        for _ in 0..<maxIterations {
            let size = min(remaining.width, remaining.height)
            let square: CGRect

            switch direction {
            case 0:
                square = CGRect(x: remaining.minX, y: remaining.minY, width: size, height: size)
                remaining = CGRect(
                    x: remaining.minX + size,
                    y: remaining.minY,
                    width: remaining.width - size,
                    height: remaining.height
                )
            case 1:
                square = CGRect(x: remaining.minX, y: remaining.minY, width: size, height: size)
                remaining = CGRect(
                    x: remaining.minX,
                    y: remaining.minY + size,
                    width: remaining.width,
                    height: remaining.height - size
                )
            case 2:
                square = CGRect(x: remaining.maxX - size, y: remaining.minY, width: size, height: size)
                remaining = CGRect(
                    x: remaining.minX,
                    y: remaining.minY,
                    width: remaining.width - size,
                    height: remaining.height
                )
            default:
                square = CGRect(x: remaining.minX, y: remaining.maxY - size, width: size, height: size)
                remaining = CGRect(
                    x: remaining.minX,
                    y: remaining.minY,
                    width: remaining.width,
                    height: remaining.height - size
                )
            }

            path.addRect(square)

            let center: CGPoint
            let startAngle: Angle
            let endAngle: Angle

            switch direction {
            case 0:
                center = CGPoint(x: square.maxX, y: square.minY)
                startAngle = .degrees(90)
                endAngle = .degrees(180)
            case 1:
                center = CGPoint(x: square.maxX, y: square.maxY)
                startAngle = .degrees(180)
                endAngle = .degrees(270)
            case 2:
                center = CGPoint(x: square.minX, y: square.maxY)
                startAngle = .degrees(270)
                endAngle = .degrees(360)
            default:
                center = CGPoint(x: square.minX, y: square.minY)
                startAngle = .degrees(0)
                endAngle = .degrees(90)
            }

            path.addArc(
                center: center,
                radius: size,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: false
            )

            if remaining.width <= 0 || remaining.height <= 0 {
                break
            }

            direction = (direction + 1) % 4
        }

        return path
    }

    private func centerPath(in rect: CGRect) -> Path {
        var path = Path()
        let minSide = min(rect.width, rect.height)
        let tick = minSide * 0.12
        let circleRadius = minSide * 0.18
        let innerRadius = circleRadius * 0.55

        path.move(to: CGPoint(x: rect.midX - tick, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX + tick, y: rect.midY))
        path.move(to: CGPoint(x: rect.midX, y: rect.midY - tick))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY + tick))

        let outerRect = CGRect(
            x: rect.midX - circleRadius,
            y: rect.midY - circleRadius,
            width: circleRadius * 2,
            height: circleRadius * 2
        )
        let innerRect = CGRect(
            x: rect.midX - innerRadius,
            y: rect.midY - innerRadius,
            width: innerRadius * 2,
            height: innerRadius * 2
        )
        path.addEllipse(in: outerRect)
        path.addEllipse(in: innerRect)

        let box = rect.insetBy(dx: rect.width * 0.28, dy: rect.height * 0.28)
        path.addRoundedRect(in: box, cornerSize: CGSize(width: minSide * 0.04, height: minSide * 0.04))
        return path
    }

    private func symmetryPath(in rect: CGRect) -> Path {
        var path = Path()
        let offset = rect.width * 0.06
        let tick = rect.height * 0.08

        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))

        path.move(to: CGPoint(x: rect.midX - tick, y: rect.minY + tick))
        path.addLine(to: CGPoint(x: rect.midX + tick, y: rect.minY + tick))
        path.move(to: CGPoint(x: rect.midX - tick, y: rect.maxY - tick))
        path.addLine(to: CGPoint(x: rect.midX + tick, y: rect.maxY - tick))

        path.move(to: CGPoint(x: rect.midX - offset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX - offset, y: rect.maxY))
        path.move(to: CGPoint(x: rect.midX + offset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + offset, y: rect.maxY))

        return path
    }

    private func leadingLinesPath(in rect: CGRect) -> Path {
        var path = Path()
        let focal = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.32)
        let lowerInset = rect.width * 0.10
        let midInset = rect.width * 0.22
        let midY = rect.minY + rect.height * 0.62

        let sources = [
            CGPoint(x: rect.minX + lowerInset, y: rect.maxY),
            CGPoint(x: rect.midX - rect.width * 0.12, y: rect.maxY),
            CGPoint(x: rect.midX + rect.width * 0.12, y: rect.maxY),
            CGPoint(x: rect.maxX - lowerInset, y: rect.maxY),
            CGPoint(x: rect.minX + midInset, y: midY),
            CGPoint(x: rect.maxX - midInset, y: midY)
        ]

        for source in sources {
            path.move(to: source)
            path.addLine(to: focal)
        }

        let dotRadius = min(rect.width, rect.height) * 0.025
        let dotRect = CGRect(
            x: focal.x - dotRadius,
            y: focal.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        )
        path.addEllipse(in: dotRect)
        return path
    }

    private func framingPath(in rect: CGRect) -> Path {
        var path = Path()
        let marginX = rect.width * 0.14
        let marginY = rect.height * 0.14
        let inner = rect.insetBy(dx: marginX, dy: marginY)
        let segment = min(inner.width, inner.height) * 0.22

        path.move(to: CGPoint(x: inner.minX, y: inner.minY + segment))
        path.addLine(to: CGPoint(x: inner.minX, y: inner.minY))
        path.addLine(to: CGPoint(x: inner.minX + segment, y: inner.minY))

        path.move(to: CGPoint(x: inner.maxX - segment, y: inner.minY))
        path.addLine(to: CGPoint(x: inner.maxX, y: inner.minY))
        path.addLine(to: CGPoint(x: inner.maxX, y: inner.minY + segment))

        path.move(to: CGPoint(x: inner.minX, y: inner.maxY - segment))
        path.addLine(to: CGPoint(x: inner.minX, y: inner.maxY))
        path.addLine(to: CGPoint(x: inner.minX + segment, y: inner.maxY))

        path.move(to: CGPoint(x: inner.maxX - segment, y: inner.maxY))
        path.addLine(to: CGPoint(x: inner.maxX, y: inner.maxY))
        path.addLine(to: CGPoint(x: inner.maxX, y: inner.maxY - segment))

        return path
    }

    private func portraitHeadroomPath(in rect: CGRect) -> Path {
        var path = Path()
        let headroomY = rect.minY + rect.height * 0.12
        let eyeLineY = rect.minY + rect.height * 0.38
        let shouldersY = rect.minY + rect.height * 0.72
        let shoulderSpan = rect.width * 0.7

        path.move(to: CGPoint(x: rect.minX, y: headroomY))
        path.addLine(to: CGPoint(x: rect.maxX, y: headroomY))
        path.move(to: CGPoint(x: rect.minX, y: eyeLineY))
        path.addLine(to: CGPoint(x: rect.maxX, y: eyeLineY))

        let ovalW = rect.width * 0.28
        let ovalH = rect.height * 0.36
        let ovalRect = CGRect(
            x: rect.midX - ovalW / 2,
            y: rect.minY + rect.height * 0.20,
            width: ovalW,
            height: ovalH
        )
        path.addEllipse(in: ovalRect)

        path.move(to: CGPoint(x: rect.midX - shoulderSpan / 2, y: shouldersY))
        path.addLine(to: CGPoint(x: rect.midX + shoulderSpan / 2, y: shouldersY))
        return path
    }

    private func diagonalsPath(in rect: CGRect) -> Path {
        var path = Path()
        let m = min(rect.width, rect.height) * 0.06

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + m, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + m))
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - m))
        path.addLine(to: CGPoint(x: rect.maxX - m, y: rect.minY))
        return path
    }

    private func trianglePath(in rect: CGRect) -> Path {
        var path = Path()
        let apex = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.18)
        let baseLeft = CGPoint(x: rect.minX, y: rect.maxY)
        let baseRight = CGPoint(x: rect.maxX, y: rect.maxY)

        path.move(to: baseLeft)
        path.addLine(to: baseRight)
        path.addLine(to: apex)
        path.addLine(to: baseLeft)

        let dotRadius = min(rect.width, rect.height) * 0.02
        let dotRect = CGRect(
            x: apex.x - dotRadius,
            y: apex.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        )
        path.addEllipse(in: dotRect)
        return path
    }

    private func layersFMBPath(in rect: CGRect) -> Path {
        var path = Path()
        let y1 = rect.minY + rect.height * 0.33
        let y2 = rect.minY + rect.height * 0.66

        path.move(to: CGPoint(x: rect.minX, y: y1))
        path.addLine(to: CGPoint(x: rect.maxX, y: y1))
        path.move(to: CGPoint(x: rect.minX, y: y2))
        path.addLine(to: CGPoint(x: rect.maxX, y: y2))

        let midBox = CGRect(
            x: rect.midX - rect.width * 0.11,
            y: rect.minY + rect.height * 0.45,
            width: rect.width * 0.22,
            height: rect.height * 0.18
        )
        path.addRect(midBox)

        let bracketSize = min(rect.width, rect.height) * 0.12
        let bracketOrigin = CGPoint(x: rect.minX + rect.width * 0.08, y: rect.maxY - rect.height * 0.08)
        path.move(to: CGPoint(x: bracketOrigin.x, y: bracketOrigin.y - bracketSize))
        path.addLine(to: bracketOrigin)
        path.addLine(to: CGPoint(x: bracketOrigin.x + bracketSize, y: bracketOrigin.y))

        let horizonY = rect.minY + rect.height * 0.18
        path.move(to: CGPoint(x: rect.minX, y: horizonY))
        path.addLine(to: CGPoint(x: rect.maxX, y: horizonY))
        return path
    }

    private func negativeSpacePath(in rect: CGRect) -> Path {
        var path = Path()
        let boundaryX = rect.minX + rect.width * 0.55
        let subjectBox = CGRect(
            x: rect.minX + rect.width * 0.62,
            y: rect.minY + rect.height * 0.18,
            width: rect.width * 0.22,
            height: rect.height * 0.22
        )

        path.move(to: CGPoint(x: boundaryX, y: rect.minY))
        path.addLine(to: CGPoint(x: boundaryX, y: rect.maxY))
        path.addRect(subjectBox)

        let markerRadius = min(rect.width, rect.height) * 0.02
        let markerRect = CGRect(
            x: subjectBox.midX - markerRadius,
            y: subjectBox.midY - markerRadius,
            width: markerRadius * 2,
            height: markerRadius * 2
        )
        path.addEllipse(in: markerRect)
        return path
    }
}

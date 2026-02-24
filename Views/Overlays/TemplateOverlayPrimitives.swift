import CoreGraphics
import Foundation

enum DiagonalType {
    case main
    case anti
}

struct Line {
    let from: CGPoint
    let to: CGPoint
    let opacity: CGFloat

    init(from: CGPoint, to: CGPoint, opacity: CGFloat = 1.0) {
        self.from = from
        self.to = to
        self.opacity = opacity
    }
}

struct Dot {
    let at: CGPoint
    let radius: CGFloat
    let opacity: CGFloat

    init(at: CGPoint, radius: CGFloat, opacity: CGFloat = 1.0) {
        self.at = at
        self.radius = radius
        self.opacity = opacity
    }
}

struct RectBox {
    let rect: CGRect
    let cornerRadius: CGFloat
    let dashed: Bool
    let opacity: CGFloat

    init(rect: CGRect, cornerRadius: CGFloat, dashed: Bool, opacity: CGFloat = 1.0) {
        self.rect = rect
        self.cornerRadius = cornerRadius
        self.dashed = dashed
        self.opacity = opacity
    }
}

struct Band {
    let yRange: ClosedRange<CGFloat>
    let label: String?
    let opacity: CGFloat

    init(yRange: ClosedRange<CGFloat>, label: String? = nil, opacity: CGFloat = 1.0) {
        self.yRange = yRange
        self.label = label
        self.opacity = opacity
    }
}

struct PathOverlay {
    let points: [CGPoint]
    let opacity: CGFloat

    init(points: [CGPoint], opacity: CGFloat = 1.0) {
        self.points = points
        self.opacity = opacity
    }
}

enum OverlayPrimitive {
    case line(Line)
    case dot(Dot)
    case rectBox(RectBox)
    case band(Band)
    case path(PathOverlay)
}

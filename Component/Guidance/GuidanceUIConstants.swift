import CoreGraphics

enum GuidanceUIConstants {
    static let defaultMaxRadiusPx: CGFloat = 120
    static let maxScaledRadiusPx: CGFloat = 220

    static func scaledMaxRadius(for containerSize: CGSize) -> CGFloat {
        let shortestSide = min(containerSize.width, containerSize.height)
        guard shortestSide > 0 else { return defaultMaxRadiusPx }
        let scaled = shortestSide * 0.22
        return clamp(scaled, min: defaultMaxRadiusPx, max: maxScaledRadiusPx)
    }

    static func clampedGuidanceOffset(
        _ guidanceOffset: CGSize,
        maxRadiusPx: CGFloat = defaultMaxRadiusPx
    ) -> CGSize {
        let maxRadius = maxRadiusPx
        let dx = guidanceOffset.width * maxRadius
        let dy = guidanceOffset.height * maxRadius
        let distance = sqrt(dx * dx + dy * dy)
        if distance <= maxRadius || distance == 0 {
            return CGSize(width: dx, height: dy)
        }
        let scale = maxRadius / distance
        return CGSize(width: dx * scale, height: dy * scale)
    }

    static func snappedGuidanceOffset(
        _ guidanceOffset: CGSize,
        maxRadiusPx: CGFloat = defaultMaxRadiusPx,
        snapRadiusPx: CGFloat = 10,
        releaseRadiusPx: CGFloat = 22
    ) -> CGSize {
        let clamped = clampedGuidanceOffset(guidanceOffset, maxRadiusPx: maxRadiusPx)
        let distance = sqrt(clamped.width * clamped.width + clamped.height * clamped.height)

        if distance <= snapRadiusPx {
            return .zero
        }
        if distance >= releaseRadiusPx {
            return clamped
        }

        let t = smoothstep((distance - snapRadiusPx) / max(0.001, releaseRadiusPx - snapRadiusPx))
        return CGSize(width: clamped.width * t, height: clamped.height * t)
    }

    private static func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(value, max))
    }

    private static func smoothstep(_ x: CGFloat) -> CGFloat {
        let t = clamp(x, min: 0, max: 1)
        return t * t * (3 - 2 * t)
    }
}

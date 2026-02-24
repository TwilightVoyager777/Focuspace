import CoreGraphics

enum GuidanceUIConstants {
    static let maxRadiusPx: CGFloat = 120

    static func clampedGuidanceOffset(_ guidanceOffset: CGSize) -> CGSize {
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
}

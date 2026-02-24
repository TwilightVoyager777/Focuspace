import CoreGraphics

// Guidance Contract (single source of truth)
// 1) subjectPoint: CGPoint (normalized 0..1) = current tracked subject center (Vision) or fallback.
// 2) targetPoint: CGPoint (normalized 0..1) = template target (center/thirds/golden/zone/diagonal projection).
// 3) guidanceVector g_template = targetPoint - subjectPoint (normalized vector in subject-motion semantics).
// 4) stabilizer consumes g_template (not UI-inverted).
// 5) UI mapping (subject semantics):
//    - g_ui = g_stable
//    - Arrow mode: dot = center + (g_ui * radiusPx), crosshair fixed at center
//    - Arrow goes Crosshair -> Dot

struct GuidanceDebugInfo {
    var templateType: String = "nil"
    var subjectPoint: CGPoint? = nil
    var targetPoint: CGPoint? = nil
    var gTemplate: CGSize = .zero
    var templateConfidence: CGFloat = 0
    var errMag: CGFloat = 0
    var subjectSource: String = "auto"
    var diagonalType: DiagonalType? = nil
    var negativeSpaceZone: CGRect? = nil
}

import CoreGraphics

struct TemplateOverlayModel {
    var templateId: String
    var strength: CGFloat
    var targetPoint: CGPoint?
    var diagonalKind: Int?
    var negativeSpaceZone: CGRect?
}

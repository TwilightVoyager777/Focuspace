import CoreGraphics

struct TemplateOverlayModel {
    var templateId: String
    var strength: CGFloat
    var targetPoint: CGPoint?
    var diagonalType: DiagonalType?
    var negativeSpaceZone: CGRect?
}

import CoreGraphics

enum DiagonalType {
    case main
    case anti
}

struct TemplateOverlayModel {
    var template: TemplateType
    var targetPoint: CGPoint
    var strength: CGFloat
    var selectedDiagonal: DiagonalType?
    var negativeSpaceZone: CGRect?
}

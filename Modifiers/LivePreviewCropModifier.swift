import SwiftUI
import AVFoundation

// 三等分网格线
struct LivePreviewCropModifier: ViewModifier {
    let horizontalScale: CGFloat

    func body(content: Content) -> some View {
        return content
            .scaleEffect(x: horizontalScale, y: 1.0, anchor: .center)
            .clipped()
    }
}

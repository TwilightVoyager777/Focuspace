import SwiftUI

struct FilteredPreviewOverlayView: View {
    @ObservedObject var cameraController: CameraSessionController

    var body: some View {
        if cameraController.isFilterPreviewActive,
           let image = cameraController.filteredPreviewImage {
            Image(decorative: image, scale: 1.0)
                .resizable()
                .scaledToFill()
                .transition(.opacity)
                .clipped()
        }
    }
}

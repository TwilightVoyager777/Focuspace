import CoreImage
import CoreVideo
import Foundation

enum LiveFilterPreviewRenderer {
    static func render(
        pixelBuffer: CVPixelBuffer,
        settings: CameraFilterSettings,
        ciContext: CIContext
    ) -> CGImage? {
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        let saturation = settings.colorOff ? 0.0 : settings.saturation

        image = image.applyingFilter(
            "CIColorControls",
            parameters: [
                kCIInputSaturationKey: saturation,
                kCIInputContrastKey: settings.contrast
            ]
        )

        image = image.applyingFilter(
            "CISharpenLuminance",
            parameters: [
                kCIInputSharpnessKey: settings.sharpness
            ]
        )

        return ciContext.createCGImage(image, from: image.extent)
    }
}

import CoreGraphics
import CoreImage
import Foundation

enum CapturedPhotoProcessor {
    static func process(
        _ data: Data,
        settings: CameraFilterSettings,
        applyFilters: Bool,
        cropRectNormalized: CGRect?,
        ciContext: CIContext
    ) -> Data? {
        guard var image = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }

        if applyFilters {
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
        }

        if let cropRectNormalized {
            image = cropImage(image, toNormalizedRect: cropRectNormalized)
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return ciContext.jpegRepresentation(of: image, colorSpace: colorSpace, options: [:])
    }

    private static func cropImage(_ image: CIImage, toNormalizedRect normalizedRect: CGRect) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }

        let cropRect = CGRect(
            x: extent.minX + normalizedRect.minX * extent.width,
            y: extent.minY + (1.0 - normalizedRect.maxY) * extent.height,
            width: normalizedRect.width * extent.width,
            height: normalizedRect.height * extent.height
        ).integral

        let safeRect = cropRect.intersection(extent)
        guard !safeRect.isNull, safeRect.width > 0, safeRect.height > 0 else { return image }
        return image.cropped(to: safeRect)
    }
}

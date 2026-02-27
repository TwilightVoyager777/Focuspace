import Accelerate
import CoreGraphics
@preconcurrency import CoreImage
import CoreMedia
import CoreVideo
import Foundation

final class SymmetryRuleEngine {
    private let ciContext = CIContext()

    func compute(
        sampleBuffer: CMSampleBuffer,
        anchorNormalized: CGPoint,
        downsampleWidth: Int = 256
    ) -> (dx: CGFloat, strength: CGFloat, confidence: CGFloat) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return (0, 0, 0)
        }

        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        guard sourceWidth > 0, sourceHeight > 0 else {
            return (0, 0, 0)
        }

        let targetWidth = max(32, downsampleWidth)
        let scale = CGFloat(targetWidth) / CGFloat(sourceWidth)
        let targetHeight = max(2, Int(CGFloat(sourceHeight) * scale))

        var grayBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_OneComponent8,
            kCVPixelBufferWidthKey: targetWidth,
            kCVPixelBufferHeightKey: targetHeight,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            targetWidth,
            targetHeight,
            kCVPixelFormatType_OneComponent8,
            attrs as CFDictionary,
            &grayBuffer
        )
        guard status == kCVReturnSuccess, let downsampledBuffer = grayBuffer else {
            return (0, 0, 0)
        }

        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
        let grayscale = sourceImage
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        ciContext.render(
            grayscale,
            to: downsampledBuffer,
            bounds: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight),
            colorSpace: CGColorSpaceCreateDeviceGray()
        )

        CVPixelBufferLockBaseAddress(downsampledBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(downsampledBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(downsampledBuffer) else {
            return (0, 0, 0)
        }

        let width = targetWidth
        let height = targetHeight
        let rowBytes = CVPixelBufferGetBytesPerRow(downsampledBuffer)

        var gray = vImage_Buffer(
            data: baseAddress,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: rowBytes
        )

        var floatData = [Float](repeating: 0, count: width * height)
        var gxData = [Float](repeating: 0, count: width * height)
        var gyData = [Float](repeating: 0, count: width * height)

        let gxKernel: [Float] = [-1, 0, 1, -2, 0, 2, -1, 0, 1]
        let gyKernel: [Float] = [-1, -2, -1, 0, 0, 0, 1, 2, 1]

        var didBuildGradient = false
        floatData.withUnsafeMutableBytes { floatBytes in
            guard let floatBase = floatBytes.baseAddress else { return }
            var floatBuffer = vImage_Buffer(
                data: floatBase,
                height: vImagePixelCount(height),
                width: vImagePixelCount(width),
                rowBytes: width * MemoryLayout<Float>.size
            )

            gxData.withUnsafeMutableBytes { gxBytes in
                guard let gxBase = gxBytes.baseAddress else { return }
                var gxBuffer = vImage_Buffer(
                    data: gxBase,
                    height: vImagePixelCount(height),
                    width: vImagePixelCount(width),
                    rowBytes: width * MemoryLayout<Float>.size
                )

                gyData.withUnsafeMutableBytes { gyBytes in
                    guard let gyBase = gyBytes.baseAddress else { return }
                    var gyBuffer = vImage_Buffer(
                        data: gyBase,
                        height: vImagePixelCount(height),
                        width: vImagePixelCount(width),
                        rowBytes: width * MemoryLayout<Float>.size
                    )

                    vImageConvert_Planar8toPlanarF(&gray, &floatBuffer, 0, 255, vImage_Flags(kvImageNoFlags))

                    vImageConvolve_PlanarF(
                        &floatBuffer,
                        &gxBuffer,
                        nil,
                        0,
                        0,
                        gxKernel,
                        3,
                        3,
                        0,
                        vImage_Flags(kvImageEdgeExtend)
                    )

                    vImageConvolve_PlanarF(
                        &floatBuffer,
                        &gyBuffer,
                        nil,
                        0,
                        0,
                        gyKernel,
                        3,
                        3,
                        0,
                        vImage_Flags(kvImageEdgeExtend)
                    )
                    didBuildGradient = true
                }
            }
        }
        guard didBuildGradient else {
            return (0, 0, 0)
        }

        let ax = clamp(anchorNormalized.x, min: 0, max: 1) * CGFloat(width - 1)
        let ay = clamp(anchorNormalized.y, min: 0, max: 1) * CGFloat(height - 1)

        let sx = max(1, 0.18 * CGFloat(width))
        let sy = max(1, 0.18 * CGFloat(height))
        let inv2sx2 = 1.0 / (2.0 * sx * sx)
        let inv2sy2 = 1.0 / (2.0 * sy * sy)

        var weightX = [Float](repeating: 0, count: width)
        var weightY = [Float](repeating: 0, count: height)

        for x in 0..<width {
            let dx = CGFloat(x) - ax
            let value = exp(-Double(dx * dx * inv2sx2))
            weightX[x] = Float(value)
        }

        for y in 0..<height {
            let dy = CGFloat(y) - ay
            let value = exp(-Double(dy * dy * inv2sy2))
            weightY[y] = Float(value)
        }

        let minWeight: Float = 0.15
        let axisX = 0.5 * CGFloat(width)

        var sumLeft: Float = 0
        var sumRight: Float = 0

        for y in 0..<height {
            let wy = weightY[y]
            let rowOffset = y * width
            for x in 0..<width {
                let w = max(minWeight, weightX[x] * wy)
                let index = rowOffset + x
                let gx = gxData[index]
                let gy = gyData[index]
                let magnitude = sqrt(gx * gx + gy * gy)
                let weighted = magnitude * w
                if CGFloat(x) < axisX {
                    sumLeft += weighted
                } else {
                    sumRight += weighted
                }
            }
        }

        let sumTotal = sumLeft + sumRight
        let pixelCount = Float(width * height)
        let verySmallThreshold: Float = 0.2 * pixelCount
        let energyThreshold: Float = 12.0 * pixelCount

        if sumTotal < verySmallThreshold {
            return (0, 0, 0)
        }

        let deltaLR = (sumLeft - sumRight) / (sumTotal + 1e-6)
        var dx = -deltaLR
        dx = min(1, max(-1, dx))

        var strength = min(1, abs(deltaLR) * 1.2)
        var confidence = min(1, sumTotal / energyThreshold)

        if confidence < 0.15 {
            dx = 0
            strength = 0
            confidence = 0
        }

        return (CGFloat(dx), CGFloat(strength), CGFloat(confidence))
    }

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(value, max))
    }
}

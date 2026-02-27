import Accelerate
import CoreGraphics
@preconcurrency import CoreImage
import CoreMedia
import CoreVideo
import Foundation

final class SubjectTrackerNCC {
    var downsampleWidth: Int = 256
    var patchRadiusPx: Int = 12
    var searchRadiusPx: Int = 32
    var lockScore: Float = 0.50
    var lostScore: Float = 0.35

    private(set) var isLocked: Bool = false
    private var templatePatch: [Float] = []
    private var templateSize: Int = 0
    private var lastPosPx: (x: Int, y: Int) = (0, 0)
    private(set) var lastScore: Float = 0
    private var badFrameCount: Int = 0
    private var badFrameLimit: Int = 5

    private let ciContext = CIContext()

    func reset() {
        isLocked = false
        templatePatch = []
        templateSize = 0
        lastPosPx = (0, 0)
        lastScore = 0
        badFrameCount = 0
    }

    func lock(sampleBuffer: CMSampleBuffer, anchorNormalized: CGPoint) {
        guard let frame = downsample(sampleBuffer: sampleBuffer) else {
            reset()
            return
        }

        let radius = patchRadiusPx
        let size = radius * 2 + 1
        let width = frame.width
        let height = frame.height

        var cx = Int(round(clamp(anchorNormalized.x, min: 0, max: 1) * CGFloat(width - 1)))
        var cy = Int(round(clamp(anchorNormalized.y, min: 0, max: 1) * CGFloat(height - 1)))
        cx = clampInt(cx, min: radius, max: width - 1 - radius)
        cy = clampInt(cy, min: radius, max: height - 1 - radius)

        guard let patch = extractPatch(frame: frame.data, width: width, height: height, centerX: cx, centerY: cy, radius: radius) else {
            reset()
            return
        }

        templatePatch = normalizePatch(patch)
        templateSize = size
        lastPosPx = (cx, cy)
        isLocked = true
        lastScore = 1.0
    }

    func update(sampleBuffer: CMSampleBuffer) -> (subjectCurrentNormalized: CGPoint?, score: Float) {
        guard isLocked, templateSize > 0 else {
            return (nil, 0)
        }

        guard let frame = downsample(sampleBuffer: sampleBuffer) else {
            return (nil, 0)
        }

        let width = frame.width
        let height = frame.height
        let radius = patchRadiusPx
        let size = radius * 2 + 1

        let minX = radius
        let maxX = width - 1 - radius
        let minY = radius
        let maxY = height - 1 - radius

        let startX = clampInt(lastPosPx.x - searchRadiusPx, min: minX, max: maxX)
        let endX = clampInt(lastPosPx.x + searchRadiusPx, min: minX, max: maxX)
        let startY = clampInt(lastPosPx.y - searchRadiusPx, min: minY, max: maxY)
        let endY = clampInt(lastPosPx.y + searchRadiusPx, min: minY, max: maxY)

        var bestScore: Float = -1
        var bestPos: (x: Int, y: Int) = lastPosPx
        var bestPatch: [Float] = []

        for y in startY...endY {
            for x in startX...endX {
                guard let patch = extractPatch(frame: frame.data, width: width, height: height, centerX: x, centerY: y, radius: radius) else {
                    continue
                }
                let score = nccScore(template: templatePatch, candidate: patch, size: size)
                if score > bestScore {
                    bestScore = score
                    bestPos = (x, y)
                    bestPatch = patch
                }
            }
        }

        if bestScore < lostScore {
            badFrameCount += 1
            lastScore = bestScore
            if badFrameCount < badFrameLimit {
                let nx = CGFloat(lastPosPx.x) / CGFloat(width)
                let ny = CGFloat(lastPosPx.y) / CGFloat(height)
                let normalized = CGPoint(x: nx, y: ny)
                return (normalized, bestScore)
            }
            return (nil, bestScore)
        }

        badFrameCount = 0
        lastPosPx = bestPos
        lastScore = bestScore

        if bestScore < lockScore {
            let nx = CGFloat(bestPos.x) / CGFloat(width)
            let ny = CGFloat(bestPos.y) / CGFloat(height)
            let normalized = CGPoint(x: nx, y: ny)
            return (normalized, bestScore)
        }

        if bestScore > 0.75, !bestPatch.isEmpty {
            let normalizedBest = normalizePatch(bestPatch)
            templatePatch = blendTemplate(current: templatePatch, update: normalizedBest, factor: 0.05)
        }

        let nx = CGFloat(bestPos.x) / CGFloat(width)
        let ny = CGFloat(bestPos.y) / CGFloat(height)
        let normalized = CGPoint(x: nx, y: ny)
        return (normalized, bestScore)
    }

    private func downsample(sampleBuffer: CMSampleBuffer) -> (data: [Float], width: Int, height: Int)? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }

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
        guard status == kCVReturnSuccess, let downsampledBuffer = grayBuffer else { return nil }

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

        guard let baseAddress = CVPixelBufferGetBaseAddress(downsampledBuffer) else { return nil }

        let rowBytes = CVPixelBufferGetBytesPerRow(downsampledBuffer)
        var gray = vImage_Buffer(
            data: baseAddress,
            height: vImagePixelCount(targetHeight),
            width: vImagePixelCount(targetWidth),
            rowBytes: rowBytes
        )

        var floatData = [Float](repeating: 0, count: targetWidth * targetHeight)
        var didConvertToFloat = false
        floatData.withUnsafeMutableBytes { floatBytes in
            guard let floatBase = floatBytes.baseAddress else { return }
            var floatBuffer = vImage_Buffer(
                data: floatBase,
                height: vImagePixelCount(targetHeight),
                width: vImagePixelCount(targetWidth),
                rowBytes: targetWidth * MemoryLayout<Float>.size
            )
            vImageConvert_Planar8toPlanarF(&gray, &floatBuffer, 0, 255, vImage_Flags(kvImageNoFlags))
            didConvertToFloat = true
        }
        guard didConvertToFloat else { return nil }

        return (floatData, targetWidth, targetHeight)
    }

    private func extractPatch(
        frame: [Float],
        width: Int,
        height: Int,
        centerX: Int,
        centerY: Int,
        radius: Int
    ) -> [Float]? {
        let size = radius * 2 + 1
        let minX = centerX - radius
        let maxX = centerX + radius
        let minY = centerY - radius
        let maxY = centerY + radius
        guard minX >= 0, minY >= 0, maxX < width, maxY < height else { return nil }

        var patch = [Float]()
        patch.reserveCapacity(size * size)
        for y in minY...maxY {
            let row = y * width
            for x in minX...maxX {
                patch.append(frame[row + x])
            }
        }
        return patch
    }

    private func normalizePatch(_ patch: [Float]) -> [Float] {
        let count = patch.count
        guard count > 0 else { return patch }

        var sum: Float = 0
        var sumsq: Float = 0
        for v in patch {
            sum += v
            sumsq += v * v
        }
        let mean = sum / Float(count)

        var norm: Float = 0
        var normalized = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let v = patch[i] - mean
            normalized[i] = v
            norm += v * v
        }
        let invNorm = norm > 1e-6 ? (1.0 / sqrt(norm)) : 0
        if invNorm == 0 { return normalized }
        for i in 0..<count {
            normalized[i] *= invNorm
        }
        return normalized
    }

    private func nccScore(template: [Float], candidate: [Float], size: Int) -> Float {
        let count = size * size
        guard count == template.count, count == candidate.count else { return -1 }

        var sum: Float = 0
        for v in candidate {
            sum += v
        }
        let mean = sum / Float(count)

        var norm: Float = 0
        var dot: Float = 0
        for i in 0..<count {
            let v = candidate[i] - mean
            norm += v * v
            dot += template[i] * v
        }
        let denom = sqrt(norm)
        if denom < 1e-6 { return -1 }
        return dot / denom
    }

    private func blendTemplate(current: [Float], update: [Float], factor: Float) -> [Float] {
        guard current.count == update.count else { return current }
        var blended = [Float](repeating: 0, count: current.count)
        let inv = 1 - factor
        var norm: Float = 0
        for i in 0..<current.count {
            let v = current[i] * inv + update[i] * factor
            blended[i] = v
            norm += v * v
        }
        let invNorm = norm > 1e-6 ? (1.0 / sqrt(norm)) : 0
        if invNorm == 0 { return blended }
        for i in 0..<blended.count {
            blended[i] *= invNorm
        }
        return blended
    }

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(value, max))
    }

    private func clampInt(_ value: Int, min: Int, max: Int) -> Int {
        Swift.max(min, Swift.min(value, max))
    }
}

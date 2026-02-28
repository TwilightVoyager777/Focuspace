import CoreGraphics
import Vision

final class VisionObjectTracker {
    let sequenceHandler = VNSequenceRequestHandler()
    var lastObservation: VNDetectedObjectObservation?
    var isTracking: Bool = false
    var lastCenterNormalized: CGPoint? = nil
    var lastConfidence: Float = 0
    var lostFrameCount: Int = 0
    let lostFrameLimit: Int = 14
    let minReliableConfidence: Float = 0.15
    var initialBoxSize: CGFloat = 0.22

    func reset() {
        lastObservation = nil
        isTracking = false
        lastCenterNormalized = nil
        lastConfidence = 0
        lostFrameCount = 0
    }

    func startTracking(tapPointNormalized: CGPoint) {
        let size = initialBoxSize
        let half = size * 0.5
        let visionPoint = convertAppPointToVisionSpace(tapPointNormalized)
        var x = visionPoint.x - half
        var y = visionPoint.y - half
        x = max(0, min(1 - size, x))
        y = max(0, min(1 - size, y))
        let rect = CGRect(x: x, y: y, width: size, height: size)
        lastObservation = VNDetectedObjectObservation(boundingBox: rect)
        isTracking = true
        lastCenterNormalized = tapPointNormalized
        lastConfidence = 1.0
        lostFrameCount = 0
    }

    func update(pixelBuffer: CVPixelBuffer) -> (center: CGPoint?, confidence: Float, isLost: Bool) {
        guard isTracking, let existingObservation = lastObservation else {
            return (nil, 0, true)
        }

        let request = VNTrackObjectRequest(detectedObjectObservation: existingObservation)
        request.trackingLevel = .accurate

        do {
            try sequenceHandler.perform([request], on: pixelBuffer)
        } catch {
            lostFrameCount += 1
            if lostFrameCount < lostFrameLimit {
                return (lastCenterNormalized, lastConfidence, false)
            }
            return (nil, 0, true)
        }

        guard let result = request.results?.first as? VNDetectedObjectObservation else {
            lostFrameCount += 1
            if lostFrameCount < lostFrameLimit {
                return (lastCenterNormalized, lastConfidence, false)
            }
            return (nil, 0, true)
        }

        lastObservation = result
        let bbox = result.boundingBox
        let center = convertVisionPointToAppSpace(CGPoint(x: bbox.midX, y: bbox.midY))
        let confidence = result.confidence

        if confidence < minReliableConfidence {
            lostFrameCount += 1
            if lostFrameCount < lostFrameLimit {
                let fallbackCenter = lastCenterNormalized ?? center
                let fallbackConfidence = max(lastConfidence * 0.7, confidence)
                lastCenterNormalized = fallbackCenter
                lastConfidence = fallbackConfidence
                return (fallbackCenter, fallbackConfidence, false)
            }
            return (lastCenterNormalized, confidence, true)
        }

        lastCenterNormalized = center
        lastConfidence = confidence
        lostFrameCount = 0
        return (center, confidence, false)
    }

    private func convertAppPointToVisionSpace(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x,
            y: 1 - point.y
        )
    }

    private func convertVisionPointToAppSpace(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x,
            y: 1 - point.y
        )
    }
}

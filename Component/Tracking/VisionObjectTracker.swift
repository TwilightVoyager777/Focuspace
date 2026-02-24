import CoreGraphics
import Vision

final class VisionObjectTracker {
    let sequenceHandler = VNSequenceRequestHandler()
    var lastObservation: VNDetectedObjectObservation?
    var isTracking: Bool = false
    var lastCenterNormalized: CGPoint? = nil
    var lastConfidence: Float = 0
    var lostFrameCount: Int = 0
    let lostFrameLimit: Int = 10
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
        var x = tapPointNormalized.x - half
        var y = tapPointNormalized.y - half
        x = max(0, min(1 - size, x))
        y = max(0, min(1 - size, y))
        let rect = CGRect(x: x, y: y, width: size, height: size)
        lastObservation = VNDetectedObjectObservation(boundingBox: rect)
        isTracking = true
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
        let center = CGPoint(x: bbox.midX, y: bbox.midY)
        lastCenterNormalized = center
        lastConfidence = result.confidence
        lostFrameCount = 0
        return (center, result.confidence, false)
    }
}

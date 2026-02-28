import CoreGraphics
import CoreMedia
import Vision

struct FaceSubjectObservation {
    let boundingBox: CGRect
    let faceCenter: CGPoint
    let eyeLineCenter: CGPoint?
    let foreheadGuide: CGPoint
    let confidence: CGFloat
}

final class FaceSubjectAnalyzer {
    private let sequenceHandler = VNSequenceRequestHandler()
    private var lastObservation: FaceSubjectObservation?
    private var lastTrackedObservation: VNDetectedObjectObservation?
    private var lastEyeLineRelativePoint: CGPoint?
    private var lastUpdateTime: CFTimeInterval = 0
    private var lastSuccessTime: CFTimeInterval = 0

    private let trackingUpdateInterval: CFTimeInterval = 0.08
    private let fullDetectionInterval: CFTimeInterval = 0.22
    private let staleGraceInterval: CFTimeInterval = 0.45
    private let trackingConfidenceFloor: VNConfidence = 0.35

    func reset() {
        lastObservation = nil
        lastTrackedObservation = nil
        lastEyeLineRelativePoint = nil
        lastUpdateTime = 0
        lastSuccessTime = 0
    }

    func update(sampleBuffer: CMSampleBuffer, now: CFTimeInterval) -> FaceSubjectObservation? {
        if now - lastUpdateTime < trackingUpdateInterval {
            return cachedObservationIfFresh(now: now)
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return cachedObservationIfFresh(now: now)
        }

        if now - lastSuccessTime < fullDetectionInterval,
           let trackedObservation = trackedObservation(from: pixelBuffer),
           let trackedFace = observation(from: trackedObservation.boundingBox) {
            lastUpdateTime = now
            lastObservation = trackedFace
            lastSuccessTime = now
            return trackedFace
        }

        lastUpdateTime = now

        let faceRequest = VNDetectFaceRectanglesRequest()
        let faceHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try faceHandler.perform([faceRequest])
        } catch {
            return cachedObservationIfFresh(now: now)
        }

        guard let faces = faceRequest.results,
              let primaryFace = preferredFace(from: faces) else {
            return cachedObservationIfFresh(now: now)
        }

        let landmarksRequest = VNDetectFaceLandmarksRequest()
        landmarksRequest.inputFaceObservations = [primaryFace]

        let landmarksHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        var eyeLineCenter: CGPoint? = nil

        do {
            try landmarksHandler.perform([landmarksRequest])
            if let landmarkFace = landmarksRequest.results?.first {
                eyeLineCenter = resolvedEyeLineCenter(for: landmarkFace)
            }
        } catch {
            eyeLineCenter = nil
        }

        let observation = buildObservation(
            boundingBox: primaryFace.boundingBox,
            eyeLineCenter: eyeLineCenter,
            confidence: clamp(CGFloat(primaryFace.confidence), min: 0, max: 1)
        )
        lastTrackedObservation = VNDetectedObjectObservation(boundingBox: primaryFace.boundingBox)
        lastEyeLineRelativePoint = eyeLineCenter.map { point in
            normalizedRelativePoint(point, in: primaryFace.boundingBox)
        }
        lastObservation = observation
        lastSuccessTime = now
        return observation
    }

    private func cachedObservationIfFresh(now: CFTimeInterval) -> FaceSubjectObservation? {
        guard let lastObservation, now - lastSuccessTime <= staleGraceInterval else {
            self.lastObservation = nil
            self.lastTrackedObservation = nil
            self.lastEyeLineRelativePoint = nil
            return nil
        }
        return lastObservation
    }

    private func preferredFace(from observations: [VNFaceObservation]) -> VNFaceObservation? {
        observations.max { lhs, rhs in
            preferenceScore(for: lhs) < preferenceScore(for: rhs)
        }
    }

    private func trackedObservation(from pixelBuffer: CVPixelBuffer) -> VNDetectedObjectObservation? {
        guard let lastTrackedObservation else {
            return nil
        }

        let request = VNTrackObjectRequest(detectedObjectObservation: lastTrackedObservation)
        request.trackingLevel = .fast

        do {
            try sequenceHandler.perform([request], on: pixelBuffer)
        } catch {
            self.lastTrackedObservation = nil
            return nil
        }

        guard let tracked = request.results?.first as? VNDetectedObjectObservation,
              tracked.confidence >= trackingConfidenceFloor else {
            self.lastTrackedObservation = nil
            return nil
        }

        self.lastTrackedObservation = tracked
        return tracked
    }

    private func observation(from boundingBox: CGRect) -> FaceSubjectObservation? {
        guard boundingBox.width > 0.02, boundingBox.height > 0.02 else {
            return nil
        }
        let eyeLineCenter = lastEyeLineRelativePoint.map { relative in
            CGPoint(
                x: clamp(boundingBox.minX + relative.x * boundingBox.width, min: 0, max: 1),
                y: clamp(boundingBox.minY + relative.y * boundingBox.height, min: 0, max: 1)
            )
        }
        return buildObservation(
            boundingBox: boundingBox,
            eyeLineCenter: eyeLineCenter,
            confidence: 0.82
        )
    }

    private func buildObservation(
        boundingBox: CGRect,
        eyeLineCenter: CGPoint?,
        confidence: CGFloat
    ) -> FaceSubjectObservation {
        let appBoundingBox = convertVisionRectToAppSpace(boundingBox)
        let appEyeLineCenter = eyeLineCenter.map(convertVisionPointToAppSpace)
        let center = CGPoint(x: appBoundingBox.midX, y: appBoundingBox.midY)
        let foreheadGuide = CGPoint(
            x: appBoundingBox.midX,
            y: clamp(appBoundingBox.minY + appBoundingBox.height * 0.08, min: 0, max: 1)
        )
        return FaceSubjectObservation(
            boundingBox: appBoundingBox,
            faceCenter: center,
            eyeLineCenter: appEyeLineCenter,
            foreheadGuide: foreheadGuide,
            confidence: confidence
        )
    }

    private func normalizedRelativePoint(_ point: CGPoint, in boundingBox: CGRect) -> CGPoint {
        guard boundingBox.width > 0.0001, boundingBox.height > 0.0001 else {
            return CGPoint(x: 0.5, y: 0.5)
        }
        return CGPoint(
            x: clamp((point.x - boundingBox.minX) / boundingBox.width, min: 0, max: 1),
            y: clamp((point.y - boundingBox.minY) / boundingBox.height, min: 0, max: 1)
        )
    }

    private func convertVisionRectToAppSpace(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: 1 - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private func convertVisionPointToAppSpace(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: 1 - point.y)
    }

    private func preferenceScore(for observation: VNFaceObservation) -> CGFloat {
        let bbox = observation.boundingBox
        let areaScore = bbox.width * bbox.height
        let dx = bbox.midX - 0.5
        let dy = bbox.midY - 0.5
        let distance = sqrt((dx * dx) + (dy * dy))
        let centralityScore = Swift.max(0, 1 - distance * 1.6)
        return (areaScore * 0.78) + (centralityScore * 0.22)
    }

    private func resolvedEyeLineCenter(for observation: VNFaceObservation) -> CGPoint? {
        let bbox = observation.boundingBox
        let landmarks = observation.landmarks
        let leftEye = landmarks?.leftEye.flatMap { averagePoint(for: $0, in: bbox) }
        let rightEye = landmarks?.rightEye.flatMap { averagePoint(for: $0, in: bbox) }

        switch (leftEye, rightEye) {
        case let (left?, right?):
            return CGPoint(
                x: (left.x + right.x) * 0.5,
                y: (left.y + right.y) * 0.5
            )
        case let (left?, nil):
            return left
        case let (nil, right?):
            return right
        case (nil, nil):
            return nil
        }
    }

    private func averagePoint(for region: VNFaceLandmarkRegion2D, in boundingBox: CGRect) -> CGPoint? {
        let count = Int(region.pointCount)
        guard count > 0 else { return nil }

        let points = region.normalizedPoints
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0

        for index in 0..<count {
            let point = points[index]
            sumX += boundingBox.minX + CGFloat(point.x) * boundingBox.width
            sumY += boundingBox.minY + CGFloat(point.y) * boundingBox.height
        }

        let scale: CGFloat = 1.0 / CGFloat(count)
        return CGPoint(x: sumX * scale, y: sumY * scale)
    }

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(max, value))
    }
}

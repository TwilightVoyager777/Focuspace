import CoreGraphics
import Foundation

final class TrackingResilienceController {
    private var lastReliableSubjectCenter: CGPoint? = nil
    private var lastReliableSubjectConfidence: Float = 0
    private var lastReliableSubjectTimestamp: CFTimeInterval = 0
    private var consecutiveTrackerLostFrames: Int = 0
    private var trackerReacquireNextAllowedTime: CFTimeInterval = 0

    private let trackerLossGraceWindow: CFTimeInterval = 0.9
    private let trackerReacquireInterval: CFTimeInterval = 0.45
    private let trackerLostFramesBeforeReacquire: Int = 4
    private let trackerReliableConfidenceFloor: Float = 0.18

    func reset() {
        lastReliableSubjectCenter = nil
        lastReliableSubjectConfidence = 0
        lastReliableSubjectTimestamp = 0
        consecutiveTrackerLostFrames = 0
        trackerReacquireNextAllowedTime = 0
    }

    func seed(at point: CGPoint, confidence: Float, now: CFTimeInterval) {
        lastReliableSubjectCenter = point
        lastReliableSubjectConfidence = confidence
        lastReliableSubjectTimestamp = now
        consecutiveTrackerLostFrames = 0
    }

    func update(
        trackedCenter: inout CGPoint?,
        trackedConfidence: inout Float,
        trackedIsLost: inout Bool,
        now: CFTimeInterval,
        fallbackAnchor: CGPoint
    ) -> CGPoint? {
        if trackedIsLost == false, let center = trackedCenter {
            if trackedConfidence >= trackerReliableConfidenceFloor {
                lastReliableSubjectCenter = center
                lastReliableSubjectConfidence = trackedConfidence
                lastReliableSubjectTimestamp = now
            } else if lastReliableSubjectCenter == nil {
                lastReliableSubjectCenter = center
                lastReliableSubjectConfidence = max(trackedConfidence, trackerReliableConfidenceFloor)
                lastReliableSubjectTimestamp = now
            }
            consecutiveTrackerLostFrames = 0
            return nil
        }

        consecutiveTrackerLostFrames += 1
        let recentFallback: CGPoint? = {
            guard let last = lastReliableSubjectCenter else { return nil }
            guard (now - lastReliableSubjectTimestamp) <= trackerLossGraceWindow else { return nil }
            return last
        }()

        if let recentFallback {
            trackedCenter = recentFallback
            trackedConfidence = max(0.12, lastReliableSubjectConfidence * 0.65)
            trackedIsLost = false
        }

        guard consecutiveTrackerLostFrames >= trackerLostFramesBeforeReacquire else { return nil }
        guard now >= trackerReacquireNextAllowedTime else { return nil }
        trackerReacquireNextAllowedTime = now + trackerReacquireInterval
        return clampNormalizedPoint(recentFallback ?? fallbackAnchor)
    }

    private func clampNormalizedPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: max(0, min(1, point.x)),
            y: max(0, min(1, point.y))
        )
    }
}

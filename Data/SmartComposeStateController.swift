import CoreGraphics
import Foundation

final class SmartComposeStateController {
    struct Snapshot {
        let isActive: Bool
        let isProcessing: Bool
    }

    struct FrameDecision {
        let shouldPublishState: Bool
        let targetZoom: CGFloat?
    }

    private struct State {
        var isActive: Bool = false
        var isProcessing: Bool = false
        var targetTemplateID: String? = nil
        var targetUIZoom: CGFloat = 1.0
        var alignedFrames: Int = 0
        var startTime: CFTimeInterval = 0
        var lastZoomAdjustTime: CFTimeInterval = 0
        var requestID: UUID? = nil
    }

    private let stateQueue = DispatchQueue(label: "camera.smart.compose.state.queue")
    private var state = State()
    private let minAlignedFrames: Int = 4
    private let maxZoomStep: CGFloat = 0.045
    private let minZoomStep: CGFloat = 0.007
    private let zoomAdjustInterval: CFTimeInterval = 0.05
    private let maxDuration: CFTimeInterval = 8.0

    let minimumZoomIncrease: CGFloat = 0.18
    let minimumProcessingDuration: CFTimeInterval = 1.25

    func beginProcessing(requestID: UUID) -> Bool {
        stateQueue.sync {
            if state.isProcessing {
                return false
            }
            state.isProcessing = true
            state.isActive = false
            state.requestID = requestID
            return true
        }
    }

    func isCurrentProcessingRequest(_ requestID: UUID) -> Bool {
        stateQueue.sync {
            state.isProcessing && state.requestID == requestID
        }
    }

    func activate(
        requestID: UUID,
        templateID: String?,
        targetZoom: CGFloat,
        now: CFTimeInterval
    ) -> Bool {
        stateQueue.sync {
            guard state.requestID == requestID else { return false }
            state.isProcessing = false
            state.isActive = true
            state.targetTemplateID = templateID
            state.targetUIZoom = targetZoom
            state.alignedFrames = 0
            state.startTime = now
            state.lastZoomAdjustTime = 0
            state.requestID = nil
            return true
        }
    }

    func snapshot() -> Snapshot {
        stateQueue.sync {
            Snapshot(isActive: state.isActive, isProcessing: state.isProcessing)
        }
    }

    func reset() {
        stateQueue.sync {
            state = State()
        }
    }

    func decisionForFrame(
        now: CFTimeInterval,
        currentTemplateID: String?,
        isHolding: Bool,
        guidanceConfidence: CGFloat,
        trackedIsLost: Bool
    ) -> FrameDecision {
        var shouldPublishState = false
        var targetZoom: CGFloat?

        stateQueue.sync {
            guard state.isActive else { return }

            if state.startTime > 0, (now - state.startTime) > maxDuration {
                state = State()
                shouldPublishState = true
                return
            }

            if let expectedTemplate = state.targetTemplateID,
               let currentTemplateID,
               expectedTemplate != currentTemplateID {
                state = State()
                shouldPublishState = true
                return
            }

            if trackedIsLost || guidanceConfidence < 0.18 {
                state.alignedFrames = max(0, state.alignedFrames - 1)
                return
            }

            if isHolding {
                state.alignedFrames += 1
            } else {
                state.alignedFrames = max(0, state.alignedFrames - 1)
            }

            guard state.alignedFrames >= minAlignedFrames else { return }
            guard (now - state.lastZoomAdjustTime) >= zoomAdjustInterval else { return }
            state.lastZoomAdjustTime = now
            targetZoom = state.targetUIZoom
        }

        return FrameDecision(shouldPublishState: shouldPublishState, targetZoom: targetZoom)
    }

    func adaptiveZoomStep(for deltaMagnitude: CGFloat) -> CGFloat {
        max(minZoomStep, min(maxZoomStep, deltaMagnitude * 0.35))
    }
}

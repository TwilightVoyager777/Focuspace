import CoreGraphics
import QuartzCore

struct GuidanceStabilizer2D {
    var stableDx: CGFloat = 0
    var stableDy: CGFloat = 0
    var smoothedDx: CGFloat = 0
    var smoothedDy: CGFloat = 0
    var isHolding: Bool = true
    var lastUpdateTime: CFTimeInterval = 0

    var confidenceMin: CGFloat = 0.2
    var deadIn: CGFloat = 0.05
    var deadOut: CGFloat = 0.08
    var vMaxPerSec: CGFloat = 3.0
    var emaTauMoving: CGFloat = 0.06
    var emaTauHolding: CGFloat = 0.18
    var outputGain: CGFloat = 1.3

    mutating func reset() {
        stableDx = 0
        stableDy = 0
        smoothedDx = 0
        smoothedDy = 0
        isHolding = true
        lastUpdateTime = 0
    }

    mutating func update(rawDx: CGFloat, rawDy: CGFloat, confidence: CGFloat, now: CFTimeInterval) -> (CGFloat, CGFloat) {
        if lastUpdateTime == 0 {
            lastUpdateTime = now
            return (stableDx, stableDy)
        }

        var dt = now - lastUpdateTime
        if dt.isNaN || dt <= 0 {
            dt = 1.0 / 60.0
        }
        dt = min(max(dt, 1.0 / 120.0), 1.0 / 15.0)
        lastUpdateTime = now

        if confidence < confidenceMin {
            return (stableDx, stableDy)
        }

        let errDx = clamp(rawDx * outputGain, min: -1, max: 1)
        let errDy = clamp(rawDy * outputGain, min: -1, max: 1)
        let errMag = sqrt(errDx * errDx + errDy * errDy)

        if !isHolding && errMag < deadIn {
            isHolding = true
        } else if isHolding && errMag > deadOut {
            isHolding = false
        }

        let tau = isHolding ? emaTauHolding : emaTauMoving
        let alpha = 1 - exp(-dt / tau)
        smoothedDx = smoothedDx + CGFloat(alpha) * (errDx - smoothedDx)
        smoothedDy = smoothedDy + CGFloat(alpha) * (errDy - smoothedDy)

        let targetDx: CGFloat = isHolding ? 0 : smoothedDx
        let targetDy: CGFloat = isHolding ? 0 : smoothedDy
        let maxStep = vMaxPerSec * CGFloat(dt)

        stableDx = stableDx + clamp(targetDx - stableDx, min: -maxStep, max: maxStep)
        stableDy = stableDy + clamp(targetDy - stableDy, min: -maxStep, max: maxStep)

        stableDx = clamp(stableDx, min: -1, max: 1)
        stableDy = clamp(stableDy, min: -1, max: 1)

        return (stableDx, stableDy)
    }

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(value, max))
    }
}

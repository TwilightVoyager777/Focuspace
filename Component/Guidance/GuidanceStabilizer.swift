import CoreGraphics
import QuartzCore

struct GuidanceStabilizer {
    var dxStable: CGFloat = 0
    var errSmoothed: CGFloat = 0
    var isHolding: Bool = true
    var lastUpdateTime: CFTimeInterval = 0
    var didFireHoldHaptic: Bool = false

    var confidenceMin: CGFloat = 0.2
    var deadIn: CGFloat = 0.05
    var deadOut: CGFloat = 0.08
    var vMaxPerSec: CGFloat = 1.2
    var emaTauMoving: CGFloat = 0.12
    var emaTauHolding: CGFloat = 0.25
    var outputGain: CGFloat = 1.0

    mutating func reset() {
        dxStable = 0
        errSmoothed = 0
        isHolding = true
        lastUpdateTime = 0
        didFireHoldHaptic = false
    }

    mutating func update(rawDx: CGFloat, confidence: CGFloat, now: CFTimeInterval) -> CGFloat {
        if lastUpdateTime == 0 {
            lastUpdateTime = now
            return dxStable
        }

        var dt = now - lastUpdateTime
        if dt.isNaN || dt <= 0 {
            dt = 1.0 / 60.0
        }
        dt = min(max(dt, 1.0 / 120.0), 1.0 / 15.0)
        lastUpdateTime = now

        if confidence < confidenceMin {
            return dxStable
        }

        let err = clamp(rawDx * outputGain, min: -1, max: 1)

        if !isHolding && abs(err) < deadIn {
            isHolding = true
        } else if isHolding && abs(err) > deadOut {
            isHolding = false
        }

        let tau = isHolding ? emaTauHolding : emaTauMoving
        let alpha = 1 - exp(-dt / tau)
        errSmoothed = errSmoothed + CGFloat(alpha) * (err - errSmoothed)

        let target: CGFloat = isHolding ? 0 : errSmoothed
        let maxStep = vMaxPerSec * CGFloat(dt)
        dxStable = dxStable + clamp(target - dxStable, min: -maxStep, max: maxStep)
        dxStable = clamp(dxStable, min: -1, max: 1)

        return dxStable
    }

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(value, max))
    }
}

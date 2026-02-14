import AVFoundation
import Foundation

struct DeviceControlCapabilities {
    let isoMin: Float
    let isoMax: Float
    let shutterMin: CMTime
    let shutterMax: CMTime
    let evMin: Float
    let evMax: Float
    let supportsWBLock: Bool
}

struct DeviceControlState {
    var iso: Float? = nil
    var shutter: CMTime? = nil
    var evBias: Float? = nil
    var wbTemperature: Float? = nil
    var wbTint: Float? = nil
}

final class DeviceControls {
    private(set) var caps: DeviceControlCapabilities? = nil
    private(set) var state: DeviceControlState = DeviceControlState()

    func refreshCapabilities(device: AVCaptureDevice) {
        let format = device.activeFormat
        caps = DeviceControlCapabilities(
            isoMin: format.minISO,
            isoMax: format.maxISO,
            shutterMin: format.minExposureDuration,
            shutterMax: format.maxExposureDuration,
            evMin: device.minExposureTargetBias,
            evMax: device.maxExposureTargetBias,
            supportsWBLock: device.isWhiteBalanceModeSupported(.locked)
        )
    }

    func applyAll(device: AVCaptureDevice) {
        if caps == nil {
            refreshCapabilities(device: device)
        }
        guard let caps else { return }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            applyExposureLocked(device: device, caps: caps)
            applyEVLocked(device: device, caps: caps)
            applyWhiteBalanceLocked(device: device, caps: caps)
        } catch {
            // ignore
        }
    }

    func setISO(_ iso: Float?, device: AVCaptureDevice) {
        state.iso = iso
        applyExposure(device: device)
    }

    func setShutter(_ duration: CMTime?, device: AVCaptureDevice) {
        state.shutter = duration
        applyExposure(device: device)
    }

    func setEV(_ bias: Float?, device: AVCaptureDevice) {
        state.evBias = bias
        applyEV(device: device)
    }

    func setWhiteBalance(temp: Float?, tint: Float?, device: AVCaptureDevice) {
        if temp == nil || tint == nil {
            state.wbTemperature = nil
            state.wbTint = nil
        } else {
            state.wbTemperature = temp
            state.wbTint = tint
        }
        applyWhiteBalance(device: device)
    }

    private func applyExposure(device: AVCaptureDevice) {
        if caps == nil {
            refreshCapabilities(device: device)
        }
        guard let caps else { return }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            applyExposureLocked(device: device, caps: caps)
        } catch {
            // ignore
        }
    }

    private func applyEV(device: AVCaptureDevice) {
        if caps == nil {
            refreshCapabilities(device: device)
        }
        guard let caps else { return }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            applyEVLocked(device: device, caps: caps)
        } catch {
            // ignore
        }
    }

    private func applyWhiteBalance(device: AVCaptureDevice) {
        if caps == nil {
            refreshCapabilities(device: device)
        }
        guard let caps else { return }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            applyWhiteBalanceLocked(device: device, caps: caps)
        } catch {
            // ignore
        }
    }

    private func applyExposureLocked(device: AVCaptureDevice, caps: DeviceControlCapabilities) {
        if state.iso != nil || state.shutter != nil {
            guard device.isExposureModeSupported(.custom) else {
                print("DeviceControls: exposure .custom not supported")
                return
            }

            let requestedDuration = state.shutter ?? device.exposureDuration
            let requestedISO = state.iso ?? device.iso
            let clampedDuration = clampDuration(requestedDuration, caps: caps)
            let clampedISO = clampISO(requestedISO, caps: caps)

            device.setExposureModeCustom(
                duration: clampedDuration,
                iso: clampedISO,
                completionHandler: nil
            )
        } else {
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            } else {
                print("DeviceControls: continuous auto exposure not supported")
            }
        }
    }

    private func applyEVLocked(device: AVCaptureDevice, caps: DeviceControlCapabilities) {
        guard let bias = state.evBias else { return }
        let clampedBias = clampEV(bias, caps: caps)
        device.setExposureTargetBias(clampedBias, completionHandler: nil)
    }

    private func applyWhiteBalanceLocked(device: AVCaptureDevice, caps: DeviceControlCapabilities) {
        guard
            let temp = state.wbTemperature,
            let tint = state.wbTint
        else {
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            } else {
                print("DeviceControls: white balance auto mode not supported")
            }
            return
        }

        guard caps.supportsWBLock else {
            print("DeviceControls: white balance lock not supported")
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            return
        }

        let values = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
            temperature: temp,
            tint: tint
        )
        let gains = device.deviceWhiteBalanceGains(for: values)
        let clampedGains = clampGains(gains, maxGain: device.maxWhiteBalanceGain)

        device.setWhiteBalanceModeLocked(with: clampedGains, completionHandler: nil)
    }

    private func clampISO(_ value: Float, caps: DeviceControlCapabilities) -> Float {
        let clamped = max(caps.isoMin, min(caps.isoMax, value))
        if clamped != value {
            print("DeviceControls: ISO clamped from \(value) to \(clamped)")
        }
        return clamped
    }

    private func clampDuration(_ value: CMTime, caps: DeviceControlCapabilities) -> CMTime {
        var clamped = value
        if CMTimeCompare(clamped, caps.shutterMin) < 0 {
            clamped = caps.shutterMin
        } else if CMTimeCompare(clamped, caps.shutterMax) > 0 {
            clamped = caps.shutterMax
        }
        if CMTimeCompare(clamped, value) != 0 {
            print("DeviceControls: shutter clamped")
        }
        return clamped
    }

    private func clampEV(_ value: Float, caps: DeviceControlCapabilities) -> Float {
        let clamped = max(caps.evMin, min(caps.evMax, value))
        if clamped != value {
            print("DeviceControls: EV bias clamped from \(value) to \(clamped)")
        }
        return clamped
    }

    private func clampGains(
        _ gains: AVCaptureDevice.WhiteBalanceGains,
        maxGain: Float
    ) -> AVCaptureDevice.WhiteBalanceGains {
        var clamped = gains
        clamped.redGain = max(1.0, min(maxGain, gains.redGain))
        clamped.greenGain = max(1.0, min(maxGain, gains.greenGain))
        clamped.blueGain = max(1.0, min(maxGain, gains.blueGain))

        if clamped.redGain != gains.redGain || clamped.greenGain != gains.greenGain || clamped.blueGain != gains.blueGain {
            print("DeviceControls: white balance gains clamped")
        }

        return clamped
    }
}

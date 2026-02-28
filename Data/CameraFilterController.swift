import Foundation

struct CameraFilterSettings: Sendable {
    var sharpness: Double
    var contrast: Double
    var saturation: Double
    var colorOff: Bool
}

final class CameraFilterController: @unchecked Sendable {
    private let settingsQueue = DispatchQueue(label: "camera.filter.settings.queue")
    private var settings = CameraFilterSettings(
        sharpness: 0.0,
        contrast: 1.0,
        saturation: 1.0,
        colorOff: false
    )

    func update(
        _ update: @escaping @Sendable (inout CameraFilterSettings) -> Void,
        onActivityChange: @escaping @Sendable (Bool) -> Void
    ) {
        settingsQueue.async { [weak self] in
            guard let self else { return }
            update(&self.settings)
            onActivityChange(Self.isActive(self.settings))
        }
    }

    func snapshot() -> CameraFilterSettings {
        settingsQueue.sync {
            settings
        }
    }

    static func isActive(_ settings: CameraFilterSettings) -> Bool {
        if settings.colorOff {
            return true
        }
        if settings.sharpness > 0.001 {
            return true
        }
        if abs(settings.contrast - 1.0) > 0.01 {
            return true
        }
        if abs(settings.saturation - 1.0) > 0.01 {
            return true
        }
        return false
    }
}

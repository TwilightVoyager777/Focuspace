@preconcurrency import AVFoundation
import Foundation
import Photos
import SwiftUI
import UIKit

// 相机会话管理（权限 + 会话配置 + 启停 + 拍照 + 录制）
final class CameraSessionController: NSObject, ObservableObject, @unchecked Sendable {
    enum State {
        case idle
        case requesting
        case authorized
        case denied
        case unavailable
        case running
    }

    enum BackLens {
        case wide
        case ultraWide
    }

    // 拍照闪光灯模式
    enum PhotoFlashMode {
        case off
        case on
        case auto
    }

    // 拍摄模式
    enum CaptureMode {
        case photo
        case video
    }

    let session: AVCaptureSession = AVCaptureSession()

    @Published private(set) var state: State = .idle
    @Published private(set) var lastCaptureSucceeded: Bool? = nil
    @Published private(set) var lastErrorMessage: String? = nil
    @Published var isShutterFlashing: Bool = false
    @Published private(set) var isFocusLocked: Bool = false
    @Published private(set) var backLens: BackLens = .wide
    @Published private(set) var minUIZoom: CGFloat = 1.0
    @Published var flashMode: PhotoFlashMode = .off
    @Published private(set) var isFlashSupported: Bool = false
    @Published var captureMode: CaptureMode = .photo
    @Published var isRecording: Bool = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var isModeSwitching: Bool = false
    @Published var isCameraSwitching: Bool = false
    @Published var previewFreeze: Bool = false
    @Published var switchSnapshot: UIImage? = nil
    @Published private(set) var cameraPosition: AVCaptureDevice.Position = .back

    private let photoOutput: AVCapturePhotoOutput = AVCapturePhotoOutput()
    private let movieOutput: AVCaptureMovieFileOutput = AVCaptureMovieFileOutput()
    // 串行队列：所有会话/输出操作都必须在这里执行，避免 libdispatch 断言崩溃
    private let sessionQueue: DispatchQueue = DispatchQueue(label: "camera.session.queue", qos: .userInitiated)
    private let sessionQueueKey: DispatchSpecificKey<Void> = DispatchSpecificKey<Void>()
    private var isConfigured: Bool = false
    private let mediaLibrary: LocalMediaLibrary
    private var currentVideoInput: AVCaptureDeviceInput? = nil
    private var currentAudioInput: AVCaptureDeviceInput? = nil
    private var currentPosition: AVCaptureDevice.Position = .back
    private var pendingRecordingID: UUID? = nil
    private var recordingTimer: Timer? = nil

    var onPreviewConnectionUpdate: ((AVCaptureDevice.Position) -> Void)?
    var snapshotProvider: (() -> UIImage?)?

    init(library: LocalMediaLibrary) {
        self.mediaLibrary = library
        super.init()
        sessionQueue.setSpecific(key: sessionQueueKey, value: ())
    }

    var exposedISORange: ClosedRange<Float>? {
        readDeviceValue { device in
            let format = device.activeFormat
            return format.minISO...format.maxISO
        }
    }

    var exposedEVRange: ClosedRange<Float>? {
        readDeviceValue { device in
            device.minExposureTargetBias...device.maxExposureTargetBias
        }
    }

    func currentISOValue() -> Float? {
        readDeviceValue { device in
            device.iso
        }
    }

    func currentExposureDurationSeconds() -> Double? {
        readDeviceValue { device in
            CMTimeGetSeconds(device.exposureDuration)
        }
    }

    func currentExposureBias() -> Float? {
        readDeviceValue { device in
            device.exposureTargetBias
        }
    }

    func currentWhiteBalanceTemperature() -> Float? {
        readDeviceValue { device in
            let values = device.temperatureAndTintValues(for: device.deviceWhiteBalanceGains)
            return values.temperature
        }
    }

    func getCurrentISO(_ completion: @escaping (Float) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentVideoInput?.device else { return }
            let value = device.iso
            DispatchQueue.main.async {
                completion(value)
            }
        }
    }

    func getCurrentShutterSeconds(_ completion: @escaping (Double) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentVideoInput?.device else { return }
            let value = CMTimeGetSeconds(device.exposureDuration)
            DispatchQueue.main.async {
                completion(value)
            }
        }
    }

    func getCurrentEV(_ completion: @escaping (Float) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentVideoInput?.device else { return }
            let value = device.exposureTargetBias
            DispatchQueue.main.async {
                completion(value)
            }
        }
    }

    func getCurrentWBTemperature(_ completion: @escaping (Float) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentVideoInput?.device else { return }
            let values = device.temperatureAndTintValues(for: device.deviceWhiteBalanceGains)
            let temperature = values.temperature
            DispatchQueue.main.async {
                completion(temperature)
            }
        }
    }

    func requestAuthorizationIfNeeded() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            await MainActor.run {
                self.state = .authorized
            }
        case .notDetermined:
            await MainActor.run {
                self.state = .requesting
            }
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            await MainActor.run {
                self.state = granted ? .authorized : .denied
            }
        default:
            await MainActor.run {
                self.state = .denied
            }
        }
    }

    func configureIfNeeded() {
        let isAuthorized = readState() == .authorized
        guard isAuthorized else { return }

        sessionQueue.async { [weak self] in
            guard let self, !self.isConfigured else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = self.captureMode == .video ? .high : .photo

            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: self.currentPosition) else {
                self.session.commitConfiguration()
                self.setState(.unavailable)
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.currentVideoInput = input
                }
            } catch {
                self.session.commitConfiguration()
                self.setState(.unavailable)
                return
            }

            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }

            if self.session.canAddOutput(self.movieOutput) {
                self.session.addOutput(self.movieOutput)
            }

            self.configurePhotoOutputConnection()
            self.configureMovieOutputConnection()
            self.session.commitConfiguration()
            self.isConfigured = true
            self.updateMinUIZoomForCurrentPosition()
            self.updateFlashSupport(for: device)
            self.setCameraPosition(self.currentPosition)
        }
    }

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.isConfigured else { return }

            if !self.session.isRunning {
                self.session.startRunning()
                self.setState(.running)
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func setCaptureMode(_ mode: CaptureMode) {
        setCaptureModeOnMain(mode)
        beginModeSwitchingAnimation()
        updateSessionPreset(for: mode)
    }

    func capturePhoto() {
        print("Shutter: mode=photo action=capturePhoto")
        // 触发快门黑闪（UI 反馈）
        DispatchQueue.main.async {
            self.isShutterFlashing = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.isShutterFlashing = false
        }

        let currentState = readState()
        guard currentState == .running || currentState == .authorized else {
            setCaptureResult(success: false, message: "Camera access required")
            return
        }

        #if targetEnvironment(simulator)
        setCaptureResult(success: false, message: "Camera unavailable on Simulator")
        return
        #endif

        sessionQueue.async { [weak self] in
            guard let self else { return }
            let settings = AVCapturePhotoSettings()

            let supported = self.readIsFlashSupported()
            if supported {
                settings.flashMode = self.flashModeToAV(self.readFlashMode())
            } else {
                settings.flashMode = .off
            }

            self.configurePhotoOutputConnection()
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func startRecording() {
        print("Shutter: mode=video action=startRecording")
        let currentState = readState()
        guard currentState == .running || currentState == .authorized else {
            setCaptureResult(success: false, message: "Camera access required")
            return
        }

        #if targetEnvironment(simulator)
        setCaptureResult(success: false, message: "Camera unavailable on Simulator")
        return
        #endif

        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.movieOutput.isRecording else { return }
            guard self.movieOutput.connection(with: .video) != nil else {
                self.setCaptureResult(success: false, message: "Video connection unavailable")
                return
            }
            self.configureMovieOutputConnection()

            self.requestMicrophoneAccessIfNeeded { granted in
                self.sessionQueue.async { [weak self] in
                    guard let self else { return }

                    if granted {
                        self.ensureAudioInput()
                    } else {
                        self.removeAudioInputIfNeeded()
                    }

                    let id = UUID()
                    Task { [weak self] in
                        guard let self else { return }
                        let outputURL = await self.makeVideoOutputURL(for: id)
                        self.sessionQueue.async { [weak self] in
                            guard let self else { return }
                            guard let outputURL else {
                                self.setCaptureResult(success: false, message: "Video output error")
                                return
                            }

                            if FileManager.default.fileExists(atPath: outputURL.path) {
                                try? FileManager.default.removeItem(at: outputURL)
                            }

                            self.pendingRecordingID = id
                            self.movieOutput.startRecording(to: outputURL, recordingDelegate: self)
                            self.setRecording(true)
                        }
                    }
                }
            }
        }
    }

    func toggleRecording() {
        guard captureMode == .video else { return }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            } else {
                let outputURL = self.makeVideoURL()
                self.configureMovieOutputConnection()
                self.movieOutput.startRecording(to: outputURL, recordingDelegate: self)

                DispatchQueue.main.async {
                    self.isRecording = true
                    self.recordingDuration = 0
                    self.startRecordingTimer()
                }
            }
        }
    }

    func stopRecording() {
        print("Shutter: mode=video action=stopRecording")
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.movieOutput.isRecording else { return }
            self.movieOutput.stopRecording()
        }
    }

    func switchCamera() {
        DispatchQueue.main.async {
            self.switchSnapshot = self.snapshotProvider?()
            withAnimation(.easeOut(duration: 0.12)) {
                self.isCameraSwitching = true
                self.previewFreeze = true
            }
        }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let currentInput = self.currentVideoInput else { return }

            let newPosition: AVCaptureDevice.Position = self.currentPosition == .back ? .front : .back
            guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else { return }

            do {
                let newInput = try AVCaptureDeviceInput(device: newDevice)

                self.session.beginConfiguration()
                self.session.removeInput(currentInput)

                if self.session.canAddInput(newInput) {
                    self.session.addInput(newInput)
                    self.currentVideoInput = newInput
                    self.currentPosition = newPosition
                    self.setBackLens(.wide)
                } else {
                    self.session.addInput(currentInput)
                }

                self.session.commitConfiguration()
                self.updateMinUIZoomForCurrentPosition()
                self.updateFlashSupport(for: newDevice)
                self.configurePhotoOutputConnection()
                self.configureMovieOutputConnection()
                self.setCameraPosition(newPosition)
                self.applyVideoConnectionsForCurrentState(position: newPosition)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    withAnimation(.easeInOut(duration: 0.18)) {
                        self?.previewFreeze = false
                        self?.isCameraSwitching = false
                        self?.switchSnapshot = nil
                    }
                }
            } catch {
                self.session.beginConfiguration()
                if !self.session.inputs.contains(currentInput) {
                    self.session.addInput(currentInput)
                }
                self.session.commitConfiguration()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    withAnimation(.easeInOut(duration: 0.18)) {
                        self?.previewFreeze = false
                        self?.isCameraSwitching = false
                        self?.switchSnapshot = nil
                    }
                }
            }
        }
    }

    // 闪光灯模式切换（off -> auto -> on -> off）
    func cycleFlashMode() {
        let isSupported = readIsFlashSupported()
        guard isSupported, readCaptureMode() == .photo else {
            setFlashMode(.off)
            return
        }

        let current = readFlashMode()
        let next: PhotoFlashMode
        switch current {
        case .off:
            next = .auto
        case .auto:
            next = .on
        case .on:
            next = .off
        }
        setFlashMode(next)
    }

    func focus(at point: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.isFocusLocked else { return }
            guard let device = self.currentVideoInput?.device else { return }

            do {
                try device.lockForConfiguration()

                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = point
                    if device.isFocusModeSupported(.autoFocus) {
                        device.focusMode = .autoFocus
                    }
                }

                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = point
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                }

                device.unlockForConfiguration()
            } catch {
                // ignore
            }
        }
    }

    func toggleFocusLock() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let device = self.currentVideoInput?.device else { return }

            do {
                try device.lockForConfiguration()

                if self.isFocusLocked {
                    if device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                    }
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                    device.isSubjectAreaChangeMonitoringEnabled = true
                    self.setFocusLocked(false)
                } else {
                    if device.isFocusModeSupported(.locked) {
                        device.focusMode = .locked
                    }
                    device.isSubjectAreaChangeMonitoringEnabled = false
                    self.setFocusLocked(true)
                }

                device.unlockForConfiguration()
            } catch {
                // ignore
            }
        }
    }

    func setISO(_ iso: Float?) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let device = self.currentVideoInput?.device else { return }

            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                if let iso {
                    guard device.isExposureModeSupported(.custom) else {
                        if device.isExposureModeSupported(.continuousAutoExposure) {
                            device.exposureMode = .continuousAutoExposure
                        }
                        return
                    }
                    let clampedISO = self.clampISO(iso, device: device)
                    let duration = device.exposureDuration
                    device.setExposureModeCustom(duration: duration, iso: clampedISO, completionHandler: nil)
                } else {
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                }
            } catch {
                // ignore
            }
        }
    }

    func setShutter(durationSeconds: Double?) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let device = self.currentVideoInput?.device else { return }

            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                if let durationSeconds {
                    guard device.isExposureModeSupported(.custom) else {
                        if device.isExposureModeSupported(.continuousAutoExposure) {
                            device.exposureMode = .continuousAutoExposure
                        }
                        return
                    }
                    let requested = CMTimeMakeWithSeconds(durationSeconds, preferredTimescale: 1_000_000_000)
                    let clampedDuration = self.clampExposureDuration(requested, device: device)
                    let iso = device.iso
                    device.setExposureModeCustom(duration: clampedDuration, iso: iso, completionHandler: nil)
                } else {
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                }
            } catch {
                // ignore
            }
        }
    }

    func setExposureBias(_ bias: Float?) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let device = self.currentVideoInput?.device else { return }

            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                let target = bias ?? 0
                let clamped = self.clampExposureBias(target, device: device)
                device.setExposureTargetBias(clamped, completionHandler: nil)
            } catch {
                // ignore
            }
        }
    }

    func setWhiteBalance(temperature: Int?, tint: Int?) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let device = self.currentVideoInput?.device else { return }

            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                guard let temperature, let tint else {
                    if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                        device.whiteBalanceMode = .continuousAutoWhiteBalance
                    }
                    return
                }

                guard device.isWhiteBalanceModeSupported(.locked) else {
                    if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                        device.whiteBalanceMode = .continuousAutoWhiteBalance
                    }
                    return
                }

                let values = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                    temperature: Float(temperature),
                    tint: Float(tint)
                )
                let gains = device.deviceWhiteBalanceGains(for: values)
                let clampedGains = self.clampWhiteBalanceGains(gains, maxGain: device.maxWhiteBalanceGain)
                device.setWhiteBalanceModeLocked(with: clampedGains, completionHandler: nil)
            } catch {
                // ignore
            }
        }
    }

    // 拍摄中连续设置变焦（不切镜头）
    func setZoomFactorWithinCurrentLens(_ uiZoom: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let device = self.currentVideoInput?.device else { return }

            if self.currentPosition == .back {
                if self.backLens == .ultraWide {
                    let t = max(0.5, min(1.0, uiZoom))
                    let mapped = 1.0 + (t - 0.5) * 2.0
                    self.applyZoom(mapped, to: device)
                } else {
                    self.applyZoom(max(uiZoom, 1.0), to: device)
                }
            } else {
                self.applyZoom(uiZoom, to: device)
            }
        }
    }

    // 手势结束时决定是否切镜头
    func finalizeZoom(_ uiZoom: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            guard self.currentPosition == .back else { return }

            let ultraWide = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
            let wide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)

            if ultraWide == nil {
                self.setMinUIZoom(1.0)
                return
            }

            self.setMinUIZoom(0.5)

            if uiZoom < 0.95 {
                if self.backLens != .ultraWide, let ultraWide {
                    self.switchBackLens(to: ultraWide, lens: .ultraWide)
                }
            } else if uiZoom > 1.05 {
                if self.backLens != .wide, let wide {
                    self.switchBackLens(to: wide, lens: .wide)
                }
            }
        }
    }

    private func switchBackLens(to device: AVCaptureDevice, lens: BackLens) {
        guard let currentInput = currentVideoInput else { return }

        do {
            let newInput = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            session.removeInput(currentInput)

            if session.canAddInput(newInput) {
                session.addInput(newInput)
                currentVideoInput = newInput
                currentPosition = .back
                setBackLens(lens)
                updateFlashSupport(for: device)
                setCameraPosition(.back)
            } else {
                session.addInput(currentInput)
            }

            session.commitConfiguration()
            configureMovieOutputConnection()
        } catch {
            session.beginConfiguration()
            if !session.inputs.contains(currentInput) {
                session.addInput(currentInput)
            }
            session.commitConfiguration()
        }
    }

    private func applyZoom(_ value: CGFloat, to device: AVCaptureDevice) {
        let minZ = device.minAvailableVideoZoomFactor
        let maxZ = device.maxAvailableVideoZoomFactor
        let z = max(minZ, min(maxZ, value))

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = z
            device.unlockForConfiguration()
        } catch {
            // ignore
        }
    }

    private func updateMinUIZoomForCurrentPosition() {
        if currentPosition == .back {
            let ultraWide = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
            setMinUIZoom(ultraWide == nil ? 1.0 : 0.5)
        } else {
            setMinUIZoom(1.0)
        }
    }

    private func updateFlashSupport(for device: AVCaptureDevice) {
        let supported = device.isFlashAvailable && photoOutput.supportedFlashModes.contains(.on)
        setFlashSupported(supported)
        if !supported {
            setFlashMode(.off)
        }
    }

    private func readDeviceValue<T>(_ read: @escaping (AVCaptureDevice) -> T?) -> T? {
        let block = { [weak self] () -> T? in
            guard let self, let device = self.currentVideoInput?.device else { return nil }
            return read(device)
        }
        if DispatchQueue.getSpecific(key: sessionQueueKey) != nil {
            return block()
        }
        return sessionQueue.sync {
            block()
        }
    }

    private func clampISO(_ value: Float, device: AVCaptureDevice) -> Float {
        let minISO = device.activeFormat.minISO
        let maxISO = device.activeFormat.maxISO
        return max(minISO, min(maxISO, value))
    }

    private func clampExposureDuration(_ value: CMTime, device: AVCaptureDevice) -> CMTime {
        let minDuration = device.activeFormat.minExposureDuration
        let maxDuration = device.activeFormat.maxExposureDuration
        if CMTimeCompare(value, minDuration) < 0 {
            return minDuration
        }
        if CMTimeCompare(value, maxDuration) > 0 {
            return maxDuration
        }
        return value
    }

    private func clampExposureBias(_ value: Float, device: AVCaptureDevice) -> Float {
        let minBias = device.minExposureTargetBias
        let maxBias = device.maxExposureTargetBias
        return max(minBias, min(maxBias, value))
    }

    private func clampWhiteBalanceGains(
        _ gains: AVCaptureDevice.WhiteBalanceGains,
        maxGain: Float
    ) -> AVCaptureDevice.WhiteBalanceGains {
        var clamped = gains
        clamped.redGain = max(1.0, min(maxGain, gains.redGain))
        clamped.greenGain = max(1.0, min(maxGain, gains.greenGain))
        clamped.blueGain = max(1.0, min(maxGain, gains.blueGain))
        return clamped
    }

    private func flashModeToAV(_ mode: PhotoFlashMode) -> AVCaptureDevice.FlashMode {
        switch mode {
        case .off:
            return .off
        case .on:
            return .on
        case .auto:
            return .auto
        }
    }

    private func ensureAudioInput() {
        guard currentAudioInput == nil else { return }
        guard let audioDevice = AVCaptureDevice.default(for: .audio) else { return }

        do {
            let audioInput = try AVCaptureDeviceInput(device: audioDevice)
            session.beginConfiguration()
            if session.canAddInput(audioInput) {
                session.addInput(audioInput)
                currentAudioInput = audioInput
            }
            session.commitConfiguration()
        } catch {
            session.commitConfiguration()
        }
    }

    private func removeAudioInputIfNeeded() {
        guard let audioInput = currentAudioInput else { return }
        session.beginConfiguration()
        session.removeInput(audioInput)
        session.commitConfiguration()
        currentAudioInput = nil
    }

    private func makeVideoOutputURL(for id: UUID) async -> URL? {
        await MainActor.run {
            mediaLibrary.makeVideoFileURL(id: id)
        }
    }

    private func requestMicrophoneAccessIfNeeded(_ completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                completion(granted)
            }
        default:
            completion(false)
        }
    }

    // 读取当前状态（避免跨线程直接访问 @Published）
    private func readState() -> State {
        if Thread.isMainThread {
            return state
        }

        return DispatchQueue.main.sync {
            state
        }
    }

    private func readFlashMode() -> PhotoFlashMode {
        if Thread.isMainThread {
            return flashMode
        }

        return DispatchQueue.main.sync {
            flashMode
        }
    }

    private func readCaptureMode() -> CaptureMode {
        if Thread.isMainThread {
            return captureMode
        }

        return DispatchQueue.main.sync {
            captureMode
        }
    }

    private func beginModeSwitchingAnimation() {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.12)) {
                self.isModeSwitching = true
            }
        }
    }

    private func finishModeSwitchingAnimation() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.easeInOut(duration: 0.18)) {
                self.isModeSwitching = false
            }
        }
    }

    private func updateSessionPreset(for mode: CaptureMode) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            defer {
                self.finishModeSwitchingAnimation()
            }
            guard self.isConfigured else { return }
            guard !self.movieOutput.isRecording else { return }

            let preset: AVCaptureSession.Preset = (mode == .video) ? .high : .photo
            guard self.session.canSetSessionPreset(preset) else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = preset
            self.session.commitConfiguration()
        }
    }

    private func readIsFlashSupported() -> Bool {
        if Thread.isMainThread {
            return isFlashSupported
        }

        return DispatchQueue.main.sync {
            isFlashSupported
        }
    }

    private func configureMovieOutputConnection() {
        guard let connection = movieOutput.connection(with: .video) else { return }
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        if connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .auto
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = (currentPosition == .front)
        }
    }

    private func configurePhotoOutputConnection() {
        guard let connection = photoOutput.connection(with: .video) else { return }
        if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = (currentPosition == .front)
        }
    }

    private func applyVideoConnectionsForCurrentState(position: AVCaptureDevice.Position) {
        if let connection = movieOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = (position == .front)
            }
        }
        if let connection = photoOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = (position == .front)
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.onPreviewConnectionUpdate?(position)
        }
    }

    private func setCameraPosition(_ position: AVCaptureDevice.Position) {
        DispatchQueue.main.async {
            self.cameraPosition = position
        }
    }

    private func setFocusLocked(_ value: Bool) {
        DispatchQueue.main.async {
            self.isFocusLocked = value
        }
    }

    private func setBackLens(_ lens: BackLens) {
        DispatchQueue.main.async {
            self.backLens = lens
        }
    }

    private func setMinUIZoom(_ value: CGFloat) {
        DispatchQueue.main.async {
            self.minUIZoom = value
        }
    }

    private func setFlashMode(_ value: PhotoFlashMode) {
        DispatchQueue.main.async {
            self.flashMode = value
        }
    }

    private func setFlashSupported(_ value: Bool) {
        DispatchQueue.main.async {
            self.isFlashSupported = value
        }
    }

    private func setCaptureModeOnMain(_ value: CaptureMode) {
        DispatchQueue.main.async {
            self.captureMode = value
        }
    }

    private func setRecording(_ value: Bool) {
        DispatchQueue.main.async {
            self.isRecording = value
        }
    }

    private func makeVideoURL() -> URL {
        let id = UUID()
        pendingRecordingID = id
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return directory.appendingPathComponent("\(id.uuidString).mov")
    }

    private func startRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.recordingDuration += 1
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingDuration = 0
    }

    var recordingDurationText: String {
        formattedTime(recordingDuration)
    }

    private func formattedTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds))
        let minutes = totalSeconds / 60
        let remaining = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, remaining)
    }

    // 主线程更新状态
    private func setState(_ newState: State) {
        DispatchQueue.main.async {
            self.state = newState
        }
    }

    // 主线程更新拍照结果
    private func setCaptureResult(success: Bool, message: String?) {
        DispatchQueue.main.async {
            self.lastCaptureSucceeded = success
            self.lastErrorMessage = message
        }
    }
}

extension CameraSessionController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if error != nil {
            setCaptureResult(success: false, message: "Capture failed")
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            setCaptureResult(success: false, message: "Capture failed")
            return
        }

        Task {
            do {
                try await mediaLibrary.savePhoto(data)
                setCaptureResult(success: true, message: nil)
            } catch {
                setCaptureResult(success: false, message: "Save failed")
            }
        }
    }
}

extension CameraSessionController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            self.isRecording = false
            self.stopRecordingTimer()
        }

        if let error {
            setCaptureResult(success: false, message: error.localizedDescription)
            return
        }

        guard let id = pendingRecordingID else {
            setCaptureResult(success: false, message: "Save failed")
            return
        }

        Task {
            logRecordedVideoMetadata(url: outputFileURL)
            do {
                try await mediaLibrary.saveVideoFile(at: outputFileURL, id: id)
                setCaptureResult(success: true, message: nil)
            } catch {
                setCaptureResult(success: false, message: "Save failed")
            }
        }
    }

    private func logRecordedVideoMetadata(url: URL) {
        let asset = AVAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else {
            print("Video metadata: no video track")
            return
        }
        let natural = track.naturalSize
        let transform = track.preferredTransform
        let displayRect = CGRect(origin: .zero, size: natural).applying(transform)
        let displaySize = CGSize(width: abs(displayRect.width), height: abs(displayRect.height))
        print("Video metadata: natural=\(natural) transform=\(transform) display=\(displaySize)")
    }
}

// 媒体条目（照片/视频）
struct MediaItem: Identifiable {
    enum MediaType {
        case photo(UIImage)
        case video(URL)
    }

    let id: UUID
    let type: MediaType
    let date: Date
}

private struct MediaRecord: Identifiable, Codable {
    enum MediaKind: String, Codable {
        case photo
        case video
    }

    let id: UUID
    let createdAt: Date
    let originalPath: String
    let thumbPath: String
    var isTrashed: Bool
    var trashedAt: Date?
    var mediaType: MediaKind
}

// 本地媒体库（照片/视频）
@MainActor
final class LocalMediaLibrary: ObservableObject {
    static let shared: LocalMediaLibrary = LocalMediaLibrary()

    @Published private(set) var items: [MediaItem] = []
    @Published var latestThumbnail: UIImage? = nil

    private var records: [MediaRecord] = []
    private let fileManager: FileManager = FileManager.default
    private let indexFileName: String = "media_index.json"

    private var libraryDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let folder = base?.appendingPathComponent("FocuspaceMedia", isDirectory: true)
        return folder ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    private var indexFileURL: URL {
        libraryDirectory.appendingPathComponent(indexFileName)
    }

    private var videoDirectory: URL {
        libraryDirectory.appendingPathComponent("Videos", isDirectory: true)
    }

    init() {
        ensureLibraryDirectory()
        loadIndex()
        updateLatestThumbnailFromItems()
    }

    // 保存照片数据到本地，并更新索引
    func savePhoto(_ data: Data) async throws {
        ensureLibraryDirectory()

        let id = UUID()
        let createdAt = Date()
        let originalURL = libraryDirectory.appendingPathComponent("\(id.uuidString).jpg")
        let thumbURL = libraryDirectory.appendingPathComponent("\(id.uuidString)_thumb.jpg")

        try data.write(to: originalURL, options: .atomic)

        guard let image = UIImage(data: data) else {
            throw NSError(domain: "LocalMediaLibrary", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image data"])
        }

        var generatedThumbnail: UIImage? = nil
        if let thumbnail = makeThumbnail(from: image, maxSize: 200) {
            generatedThumbnail = thumbnail
            if let thumbData = thumbnail.jpegData(compressionQuality: 0.8) {
                try thumbData.write(to: thumbURL, options: .atomic)
            }
        }

        let record = MediaRecord(
            id: id,
            createdAt: createdAt,
            originalPath: originalURL.path,
            thumbPath: thumbURL.path,
            isTrashed: false,
            trashedAt: nil,
            mediaType: .photo
        )

        let item = MediaItem(
            id: id,
            type: .photo(image),
            date: createdAt
        )

        records.insert(record, at: 0)
        items.insert(item, at: 0)
        if let generatedThumbnail {
            // 保存后立即更新缩略图（主线程）
            latestThumbnail = generatedThumbnail
        } else {
            updateLatestThumbnailFromItems()
        }
        saveIndex()
    }

    // 保存视频文件到本地，并更新索引
    func saveVideoFile(at url: URL, id: UUID) async throws {
        ensureLibraryDirectory()
        ensureVideoDirectory()

        let createdAt = Date()
        let originalURL = videoDirectory.appendingPathComponent("\(id.uuidString).mov")
        let thumbURL = libraryDirectory.appendingPathComponent("\(id.uuidString)_thumb.jpg")

        if fileManager.fileExists(atPath: originalURL.path) {
            try fileManager.removeItem(at: originalURL)
        }
        try fileManager.moveItem(at: url, to: originalURL)

        let record = MediaRecord(
            id: id,
            createdAt: createdAt,
            originalPath: originalURL.path,
            thumbPath: thumbURL.path,
            isTrashed: false,
            trashedAt: nil,
            mediaType: .video
        )

        let item = MediaItem(
            id: id,
            type: .video(originalURL),
            date: createdAt
        )

        records.insert(record, at: 0)
        items.insert(item, at: 0)
        updateLatestThumbnailFromItems()
        saveIndex()
    }

    func makeVideoFileURL(id: UUID) -> URL {
        ensureLibraryDirectory()
        ensureVideoDirectory()
        return videoDirectory.appendingPathComponent("\(id.uuidString).mov")
    }

    // 标记为回收站（不删除文件）
    func moveToTrash(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }

        records = records.map { record in
            if ids.contains(record.id) {
                var updated = record
                updated.isTrashed = true
                updated.trashedAt = Date()
                return updated
            }
            return record
        }
        updateLatestThumbnailFromItems()
        saveIndex()
    }

    // 从回收站恢复
    func restoreFromTrash(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }

        records = records.map { record in
            if ids.contains(record.id) {
                var updated = record
                updated.isTrashed = false
                updated.trashedAt = nil
                return updated
            }
            return record
        }
        updateLatestThumbnailFromItems()
        saveIndex()
    }

    // 永久删除（删除文件）
    func deletePermanently(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }

        let removedRecords = records.filter { ids.contains($0.id) }
        for record in removedRecords {
            do {
                try fileManager.removeItem(atPath: record.originalPath)
            } catch {
                print("Delete original failed:", error.localizedDescription)
            }

            do {
                try fileManager.removeItem(atPath: record.thumbPath)
            } catch {
                print("Delete thumb failed:", error.localizedDescription)
            }
        }

        records.removeAll { ids.contains($0.id) }
        items.removeAll { ids.contains($0.id) }
        updateLatestThumbnailFromItems()
        saveIndex()
    }

    // 导出到系统相册（手动触发）
    func exportToPhotos(ids: Set<UUID>) async -> Bool {
        guard !ids.isEmpty else { return false }

        let targets = records.filter { ids.contains($0.id) }
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    guard status == .authorized || status == .limited else {
                        continuation.resume(returning: false)
                        return
                    }

                    PHPhotoLibrary.shared().performChanges({
                        for record in targets {
                            switch record.mediaType {
                            case .photo:
                                if let image = UIImage(contentsOfFile: record.originalPath) {
                                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                                }
                            case .video:
                                let url = URL(fileURLWithPath: record.originalPath)
                                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                            }
                        }
                    }, completionHandler: { success, error in
                        DispatchQueue.main.async {
                            if success {
                                print("Export success")
                            } else {
                                print("Export failed:", error?.localizedDescription ?? "")
                            }
                            continuation.resume(returning: success)
                        }
                    })
                }
            }
        }
    }

    private var itemsByID: [UUID: MediaItem] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    private func rebuildItemsFromRecords() {
        items = records
            .sorted { $0.createdAt > $1.createdAt }
            .compactMap { makeMediaItem(from: $0) }
    }

    private func makeMediaItem(from record: MediaRecord) -> MediaItem? {
        switch record.mediaType {
        case .photo:
            guard let image = UIImage(contentsOfFile: record.originalPath) else { return nil }
            return MediaItem(id: record.id, type: .photo(image), date: record.createdAt)
        case .video:
            let url = URL(fileURLWithPath: record.originalPath)
            return MediaItem(id: record.id, type: .video(url), date: record.createdAt)
        }
    }

    // 素材列表（未删除）
    var materials: [MediaItem] {
        let map = itemsByID
        return records
            .filter { !$0.isTrashed }
            .sorted { $0.createdAt > $1.createdAt }
            .compactMap { map[$0.id] }
    }

    // 回收站列表
    var trashed: [MediaItem] {
        let map = itemsByID
        return records
            .filter { $0.isTrashed }
            .sorted { ($0.trashedAt ?? $0.createdAt) > ($1.trashedAt ?? $1.createdAt) }
            .compactMap { map[$0.id] }
    }

    // 从索引加载
    private func loadIndex() {
        guard fileManager.fileExists(atPath: indexFileURL.path) else { return }

        do {
            let data = try Data(contentsOf: indexFileURL)
            let decoded = try JSONDecoder().decode([MediaRecord].self, from: data)
            records = decoded.sorted { $0.createdAt > $1.createdAt }
            rebuildItemsFromRecords()
        } catch {
            records = []
            items = []
        }
    }

    // 保存索引（原子写入）
    private func saveIndex() {
        do {
            let data = try JSONEncoder().encode(records)
            let tempURL = libraryDirectory.appendingPathComponent("media_index.tmp")
            try data.write(to: tempURL, options: .atomic)

            if fileManager.fileExists(atPath: indexFileURL.path) {
                try fileManager.removeItem(at: indexFileURL)
            }
            try fileManager.moveItem(at: tempURL, to: indexFileURL)
        } catch {
            // ignore
        }
    }

    private func ensureLibraryDirectory() {
        if !fileManager.fileExists(atPath: libraryDirectory.path) {
            try? fileManager.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        }
    }

    private func ensureVideoDirectory() {
        if !fileManager.fileExists(atPath: videoDirectory.path) {
            try? fileManager.createDirectory(at: videoDirectory, withIntermediateDirectories: true)
        }
    }

    // 使用条目生成缩略图
    func loadThumbnail(for item: MediaItem) -> UIImage? {
        switch item.type {
        case .photo(let image):
            return makeThumbnail(from: image, maxSize: 200) ?? image
        case .video(let url):
            return generateVideoThumbnail(url: url, maxSize: 220)
        }
    }

    // 更新最新缩略图（用于相机页左下角）
    private func updateLatestThumbnailFromItems() {
        if let first = materials.first, let image = loadThumbnail(for: first) {
            latestThumbnail = image
        } else {
            latestThumbnail = nil
        }
    }

    private func makeThumbnail(from image: UIImage, maxSize: CGFloat) -> UIImage? {
        let size = image.size
        let scale = min(maxSize / size.width, maxSize / size.height)
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func generateVideoThumbnail(url: URL, maxSize: CGFloat) -> UIImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        do {
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            let image = UIImage(cgImage: cgImage)
            return makeThumbnail(from: image, maxSize: maxSize)
        } catch {
            return nil
        }
    }
}

@preconcurrency import AVFoundation
import CoreImage
import CoreVideo
import Foundation
import QuartzCore
import SwiftUI
import UIKit
import Vision

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
    @Published var isLevelOverlayEnabled: Bool = false
    @Published private(set) var filteredPreviewImage: CGImage? = nil
    @Published private(set) var isFilterPreviewActive: Bool = false
    @Published private(set) var rawSymmetryDx: CGFloat = 0
    @Published private(set) var rawSymmetryDy: CGFloat = 0
    @Published private(set) var rawSymmetryStrength: CGFloat = 0
    @Published private(set) var rawSymmetryConfidence: CGFloat = 0
    @Published private(set) var stableSymmetryDx: CGFloat = 0
    @Published private(set) var stableSymmetryDy: CGFloat = 0
    @Published private(set) var stableSymmetryIsHolding: Bool = true
    @Published private(set) var overlayTargetPoint: CGPoint? = nil
    @Published private(set) var overlayDiagonalType: DiagonalType? = nil
    @Published private(set) var overlayNegativeSpaceZone: CGRect? = nil
    @Published private(set) var selectedTemplateID: String? = nil
    @Published private(set) var templateSupportMessage: String? = nil
    @Published private(set) var effectiveAnchorNormalized: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @Published private(set) var subjectCurrentNormalized: CGPoint? = nil
    @Published private(set) var subjectTrackScore: Float = 0
    @Published private(set) var subjectIsLost: Bool = true
    @Published private(set) var aiCoachInstruction: String = ""
    @Published private(set) var aiCoachScore: Int = 0
    @Published private(set) var aiCoachShouldHold: Bool = false
    @Published private(set) var aiCoachReason: String = ""
    @Published private(set) var aiCoachSuggestedTemplateID: String? = nil
    @Published private(set) var aiCoachSuggestedTemplateReason: String? = nil
    @Published private(set) var aiCoachAvailabilityMessage: String? = nil
    @Published private(set) var isSmartComposeActive: Bool = false
    @Published private(set) var isSmartComposeProcessing: Bool = false

    private let frameGuidanceCoordinator = FrameGuidanceCoordinator()
    private var subjectTracker = SubjectTrackerNCC()
    private var visionTracker = VisionObjectTracker()
    private var faceSubjectAnalyzer = FaceSubjectAnalyzer()
    private let aiCoachCoordinator = AICoachCoordinator()
    private var latestSampleBuffer: CMSampleBuffer? = nil
    private let subjectTrackingQueue: DispatchQueue = DispatchQueue(label: "camera.subject.tracking.queue")
    private let trackingResilienceController = TrackingResilienceController()
    private let smartComposeController = SmartComposeStateController()
    private let aiCoachInterval: CFTimeInterval = 0.7
    private var aiCoachNextAllowedTime: CFTimeInterval = 0
    private var aiCoachInFlight: Bool = false
    private var templateSupportMessageToken: UUID = UUID()
    private var isUserAnchorActive: Bool = false
    private var userAnchorSetTime: CFTimeInterval = 0
    private let userAnchorLossTimeout: CFTimeInterval = 0.8
    private let userAnchorReleaseConfidence: Float = 0.35
    private let userAnchorMatchRadius: CGFloat = 0.20

    private(set) var currentAutoFocusAnchorNormalized: CGPoint = CGPoint(x: 0.5, y: 0.5)
    private(set) var userSubjectAnchorNormalized: CGPoint? = nil
    var effectiveSubjectAnchorNormalized: CGPoint {
        userSubjectAnchorNormalized ?? currentAutoFocusAnchorNormalized
    }

    private let photoOutput: AVCapturePhotoOutput = AVCapturePhotoOutput()
    private let movieOutput: AVCaptureMovieFileOutput = AVCaptureMovieFileOutput()
    private let videoDataOutput: AVCaptureVideoDataOutput = AVCaptureVideoDataOutput()
    private let videoDataOutputQueue: DispatchQueue = DispatchQueue(label: "camera.video.output.queue", qos: .userInitiated)
    private let ciContext: CIContext = CIContext()
    // 串行队列：所有会话/输出操作都必须在这里执行，避免 libdispatch 断言崩溃
    private let sessionQueue: DispatchQueue = DispatchQueue(label: "camera.session.queue", qos: .userInitiated)
    private let sessionQueueKey: DispatchSpecificKey<Void> = DispatchSpecificKey<Void>()
    private var isConfigured: Bool = false
    private let mediaLibrary: LocalMediaLibrary
    private let recordingStateController = RecordingStateController()
    private var currentVideoInput: AVCaptureDeviceInput? = nil
    private var currentPosition: AVCaptureDevice.Position = .back
    private let photoCropStateQueue: DispatchQueue = DispatchQueue(label: "camera.photo.crop.state.queue")
    private var pendingPhotoCropRectByID: [Int64: CGRect] = [:]

    var snapshotProvider: (() -> UIImage?)?
    var previewVisibleRectProvider: (() -> CGRect?)?

    init(library: LocalMediaLibrary) {
        self.mediaLibrary = library
        super.init()
        sessionQueue.setSpecific(key: sessionQueueKey, value: ())
    }

    private let filterController = CameraFilterController()
    private var hdrEnabled: Bool = false

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

    func isHDRSupported() -> Bool {
        supportsHighResolutionPhotoCapture()
    }

    private func supportsHighResolutionPhotoCapture() -> Bool {
        let dimensions = photoOutput.maxPhotoDimensions
        return dimensions.width > 0 && dimensions.height > 0
    }

    func setHDR(_ on: Bool) {
        hdrEnabled = on
    }

    func setFilterSharpness(_ value: Double) {
        updateFilterSettings { settings in
            settings.sharpness = value
        }
    }

    func setFilterContrast(_ value: Double) {
        updateFilterSettings { settings in
            settings.contrast = value
        }
    }

    func setFilterSaturation(_ value: Double) {
        updateFilterSettings { settings in
            settings.saturation = value
        }
    }

    func setFilterColorOff(_ value: Bool) {
        updateFilterSettings { settings in
            settings.colorOff = value
        }
    }

    private func currentFilterSettings() -> CameraFilterSettings {
        filterController.snapshot()
    }

    private func updateFilterSettings(_ update: @escaping @Sendable (inout CameraFilterSettings) -> Void) {
        filterController.update(update) { [weak self] isActive in
            guard let self else { return }
            Task { @MainActor in
                self.isFilterPreviewActive = isActive
                if !isActive {
                    self.filteredPreviewImage = nil
                }
            }
        }
    }

    private func isFilterActive(_ settings: CameraFilterSettings) -> Bool {
        CameraFilterController.isActive(settings)
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

    func getCurrentISO(_ completion: @escaping @Sendable (Float) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentVideoInput?.device else { return }
            let value = device.iso
            DispatchQueue.main.async {
                completion(value)
            }
        }
    }

    func getCurrentShutterSeconds(_ completion: @escaping @Sendable (Double) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentVideoInput?.device else { return }
            let value = CMTimeGetSeconds(device.exposureDuration)
            DispatchQueue.main.async {
                completion(value)
            }
        }
    }

    func getCurrentEV(_ completion: @escaping @Sendable (Float) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentVideoInput?.device else { return }
            let value = device.exposureTargetBias
            DispatchQueue.main.async {
                completion(value)
            }
        }
    }

    func getCurrentWBTemperature(_ completion: @escaping @Sendable (Float) -> Void) {
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

            guard let device = self.defaultCameraDevice(for: self.currentPosition) else {
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

            if self.session.canAddOutput(self.videoDataOutput) {
                self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
                self.videoDataOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                self.videoDataOutput.setSampleBufferDelegate(self, queue: self.videoDataOutputQueue)
                self.session.addOutput(self.videoDataOutput)
            }

            self.updateOutputsForMode(self.captureMode)

            self.resetFocusAnchorsToCenter()
            self.applyContinuousAutoFocusAnchor(to: device)
            self.configurePhotoOutputConnection()
            self.configureMovieOutputConnection()
            self.configureVideoDataOutputConnection()
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
                if let device = self.currentVideoInput?.device {
                    self.resetFocusAnchorsToCenter()
                    self.applyContinuousAutoFocusAnchor(to: device)
                }
                self.session.startRunning()
                self.setState(.running)
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func setCaptureMode(_ mode: CaptureMode) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.readCaptureMode() != mode else { return }
            guard !self.movieOutput.isRecording else {
                self.setCaptureResult(success: false, message: "Stop recording before switching modes")
                return
            }

            self.beginModeSwitchingAnimation()
            defer {
                self.finishModeSwitchingAnimation()
            }

            if self.isConfigured {
                let preset: AVCaptureSession.Preset = (mode == .video) ? .high : .photo
                guard self.session.canSetSessionPreset(preset) else { return }

                self.session.beginConfiguration()
                self.session.sessionPreset = preset
                self.updateOutputsForMode(mode)
                self.session.commitConfiguration()
                self.configureMovieOutputConnection()
                self.configureVideoDataOutputConnection()
            }

            self.setCaptureModeOnMain(mode)
        }
    }

    func setSelectedTemplate(_ id: String?) {
        if let id, !CompositionTemplateType.isSupportedTemplateID(id) {
            showTemplateSupportMessage(for: id)
            return
        }

        let resolvedID = CompositionTemplateType.canonicalID(for: id)
        clearTemplateSupportMessage()
        DispatchQueue.main.async {
            self.selectedTemplateID = resolvedID
            self.overlayTargetPoint = nil
            self.overlayDiagonalType = nil
            self.overlayNegativeSpaceZone = nil
            if resolvedID == nil {
                self.rawSymmetryDx = 0
                self.rawSymmetryDy = 0
                self.rawSymmetryStrength = 0
                self.rawSymmetryConfidence = 0
                self.stableSymmetryDx = 0
                self.stableSymmetryDy = 0
                self.stableSymmetryIsHolding = true
                self.subjectCurrentNormalized = nil
                self.subjectTrackScore = 0
                self.subjectIsLost = true
            }
        }
        if resolvedID == nil {
            frameGuidanceCoordinator.reset()
            resetTrackingResilienceState()
            stopSmartCompose()
            subjectTrackingQueue.async {
                self.subjectTracker.reset()
                self.visionTracker.reset()
                self.faceSubjectAnalyzer.reset()
            }
        } else {
            resetTrackingResilienceState()
            // Entering template mode: bootstrap tracker from current autofocus anchor.
            sessionQueue.async { [weak self] in
                guard let self else { return }
                self.userSubjectAnchorNormalized = nil
                self.isUserAnchorActive = false
                self.userAnchorSetTime = 0
                self.updateEffectiveAnchor()
                let autoAnchor = self.currentAutoFocusAnchorNormalized
                self.subjectTrackingQueue.async { [weak self] in
                    guard let self else { return }
                    self.faceSubjectAnalyzer.reset()
                    self.visionTracker.startTracking(tapPointNormalized: autoAnchor)
                    if let sampleBuffer = self.latestSampleBuffer,
                       let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                        let result = self.visionTracker.update(pixelBuffer: pixelBuffer)
                        DispatchQueue.main.async {
                            self.subjectCurrentNormalized = result.center
                            self.subjectTrackScore = result.confidence
                            self.subjectIsLost = result.isLost
                        }
                    }
                }
            }
        }
    }

    func isTemplateSupported(_ id: String) -> Bool {
        CompositionTemplateType.isSupportedTemplateID(id)
    }

    func notifyUnsupportedTemplateSelection(_ id: String) {
        showTemplateSupportMessage(for: id)
    }

    func triggerSmartComposeRecommendation(_ applyTemplate: @MainActor @Sendable @escaping (String?) -> Void) {
        guard !isRecording else {
            setCaptureResult(success: false, message: "Stop recording before using Smart Compose")
            return
        }
        let requestID = UUID()
        let processingStart = CACurrentMediaTime()
        let shouldStart = smartComposeController.beginProcessing(requestID: requestID)
        guard shouldStart else { return }
        publishSmartComposeState()

        let snapshot = buildAICoachSnapshotForSmartCompose()
        Task { [weak self] in
            guard let self else { return }
            let advice = await self.aiCoachCoordinator.evaluate(snapshot: snapshot)
            let resolvedTemplate = SmartComposeRecommendationResolver.resolveTemplateDecision(
                adviceTemplateID: advice.suggestedTemplateID,
                adviceReason: advice.suggestedTemplateReason,
                snapshot: snapshot
            )
            let finalTemplate = resolvedTemplate.id
            let finalTemplateReason = resolvedTemplate.reason
            let currentZoom = self.readCurrentUIZoomEstimate()
            let targetZoom = SmartComposeRecommendationResolver.recommendedZoom(
                templateID: finalTemplate,
                score: advice.score,
                currentZoom: currentZoom,
                minimumZoomIncrease: self.smartComposeController.minimumZoomIncrease
            )
            let elapsed = CACurrentMediaTime() - processingStart
            let remainingDelay = max(0, self.smartComposeController.minimumProcessingDuration - elapsed)

            DispatchQueue.main.asyncAfter(deadline: .now() + remainingDelay) {
                let isCurrentRequest = self.smartComposeController.isCurrentProcessingRequest(requestID)
                guard isCurrentRequest else { return }

                let now = CACurrentMediaTime()
                self.aiCoachInstruction = advice.instruction
                self.aiCoachScore = advice.score
                self.aiCoachShouldHold = advice.shouldHold
                self.aiCoachReason = advice.reason
                self.aiCoachSuggestedTemplateID = finalTemplate
                self.aiCoachSuggestedTemplateReason = finalTemplateReason
                if let message = advice.availabilityMessage {
                    self.aiCoachAvailabilityMessage = message
                } else if advice.usedFoundationModel {
                    self.aiCoachAvailabilityMessage = nil
                }
                applyTemplate(finalTemplate)
                guard self.smartComposeController.activate(
                    requestID: requestID,
                    templateID: finalTemplate,
                    targetZoom: targetZoom,
                    now: now
                ) else { return }
                self.publishSmartComposeState()
            }
        }
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

            if self.hdrEnabled && self.supportsHighResolutionPhotoCapture() {
                settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
                settings.photoQualityPrioritization = .quality
            }

            let supported = self.readIsFlashSupported()
            if supported {
                settings.flashMode = self.flashModeToAV(self.readFlashMode())
            } else {
                settings.flashMode = .off
            }

            let visibleRect = self.readPreviewVisibleRectNormalized()
            self.storePendingPhotoCropRect(visibleRect, for: settings.uniqueID)
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
            guard self.readCaptureMode() == .video else { return }
            guard !self.movieOutput.isRecording else { return }
            guard self.movieOutput.connection(with: .video) != nil else {
                self.setCaptureResult(success: false, message: "Video connection unavailable")
                return
            }
            let outputURL = self.prepareRecordingOutputURL()
            self.configureMovieOutputConnection()
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }
            self.movieOutput.startRecording(to: outputURL, recordingDelegate: self)
            self.beginRecordingUIState()
        }
    }

    func toggleRecording() {
        guard captureMode == .video else { return }

        if isRecording {
            stopRecording()
        } else {
            startRecording()
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
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.movieOutput.isRecording else {
                self.setCaptureResult(success: false, message: "Stop recording before switching cameras")
                return
            }
            guard let currentInput = self.currentVideoInput else { return }

            let newPosition: AVCaptureDevice.Position = self.currentPosition == .back ? .front : .back
            guard let newDevice = self.defaultCameraDevice(for: newPosition) else { return }
            let snapshot = DispatchQueue.main.sync {
                self.snapshotProvider?()
            }
            DispatchQueue.main.async {
                self.switchSnapshot = snapshot
                withAnimation(.easeOut(duration: 0.12)) {
                    self.isCameraSwitching = true
                    self.previewFreeze = true
                }
            }

            do {
                let newInput = try AVCaptureDeviceInput(device: newDevice)

                self.session.beginConfiguration()
                self.session.removeInput(currentInput)

                if self.session.canAddInput(newInput) {
                    self.session.addInput(newInput)
                    self.currentVideoInput = newInput
                    self.currentPosition = newPosition
                    self.setBackLens(.wide)
                    self.resetFocusAnchorsToCenter()
                    self.applyContinuousAutoFocusAnchor(to: newDevice)
                } else {
                    self.session.addInput(currentInput)
                }

                self.session.commitConfiguration()
                self.updateMinUIZoomForCurrentPosition()
                self.updateFlashSupport(for: newDevice)
                self.configurePhotoOutputConnection()
                self.configureMovieOutputConnection()
                self.applyVideoConnectionsForCurrentState(position: newPosition)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                    withAnimation(.easeInOut(duration: 0.18)) {
                        self?.cameraPosition = newPosition
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

            self.currentAutoFocusAnchorNormalized = point
            self.userSubjectAnchorNormalized = point
            self.isUserAnchorActive = true
            let now = CACurrentMediaTime()
            self.userAnchorSetTime = now
            self.updateEffectiveAnchor()
            self.resetTrackingResilienceState()
            self.trackingResilienceController.seed(at: point, confidence: 1.0, now: now)

            self.subjectTrackingQueue.async { [weak self] in
                guard let self else { return }
                self.visionTracker.startTracking(tapPointNormalized: point)
                if let sampleBuffer = self.latestSampleBuffer,
                   let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    let result = self.visionTracker.update(pixelBuffer: pixelBuffer)
                    DispatchQueue.main.async {
                        self.subjectCurrentNormalized = result.center
                        self.subjectTrackScore = result.confidence
                        self.subjectIsLost = result.isLost
                    }
                }
            }

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
                    if device.isFocusPointOfInterestSupported {
                        device.focusPointOfInterest = self.currentAutoFocusAnchorNormalized
                    }
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                    if device.isExposurePointOfInterestSupported {
                        device.exposurePointOfInterest = self.currentAutoFocusAnchorNormalized
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
    func setZoomFactorWithinCurrentLens(_ uiZoom: CGFloat, smooth: Bool = false) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let device = self.currentVideoInput?.device else { return }

            if self.currentPosition == .back {
                if self.backLens == .ultraWide {
                    let t = max(0.5, min(1.0, uiZoom))
                    let mapped = 1.0 + (t - 0.5) * 2.0
                    self.applyZoom(mapped, to: device, smooth: smooth)
                } else {
                    self.applyZoom(max(uiZoom, 1.0), to: device, smooth: smooth)
                }
            } else {
                self.applyZoom(uiZoom, to: device, smooth: smooth)
            }
        }
    }

    // 手势结束时决定是否切镜头
    func finalizeZoom(_ uiZoom: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.movieOutput.isRecording else { return }
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
        guard !movieOutput.isRecording else { return }
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

    private func applyZoom(_ value: CGFloat, to device: AVCaptureDevice, smooth: Bool = false) {
        let minZ = device.minAvailableVideoZoomFactor
        let maxZ = device.maxAvailableVideoZoomFactor
        let z = max(minZ, min(maxZ, value))

        do {
            try device.lockForConfiguration()
            if smooth {
                let delta = abs(device.videoZoomFactor - z)
                if delta < 0.003 {
                    device.videoZoomFactor = z
                } else {
                    let rate = max(8.0, min(24.0, Float(delta) * 28.0))
                    device.ramp(toVideoZoomFactor: z, withRate: rate)
                }
            } else {
                if device.isRampingVideoZoom {
                    device.cancelVideoZoomRamp()
                }
                device.videoZoomFactor = z
            }
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

    private func resetFocusAnchorsToCenter() {
        currentAutoFocusAnchorNormalized = CGPoint(x: 0.5, y: 0.5)
        userSubjectAnchorNormalized = nil
        isUserAnchorActive = false
        userAnchorSetTime = 0
        resetTrackingResilienceState()
        updateEffectiveAnchor()
        subjectTrackingQueue.async {
            self.subjectTracker.reset()
            self.visionTracker.reset()
        }
        DispatchQueue.main.async {
            self.subjectCurrentNormalized = nil
            self.subjectTrackScore = 0
            self.subjectIsLost = true
        }
    }

    private func applyContinuousAutoFocusAnchor(to device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()

            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = currentAutoFocusAnchorNormalized
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
            }

            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = currentAutoFocusAnchorNormalized
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
            }

            device.unlockForConfiguration()
        } catch {
            // ignore
        }
    }

    private func updateEffectiveAnchor() {
        DispatchQueue.main.async {
            self.effectiveAnchorNormalized = self.effectiveSubjectAnchorNormalized
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

    private func readSelectedTemplateID() -> String? {
        if Thread.isMainThread {
            return selectedTemplateID
        }

        return DispatchQueue.main.sync {
            selectedTemplateID
        }
    }

    private func readSubjectCurrentNormalized() -> CGPoint? {
        if Thread.isMainThread {
            return subjectCurrentNormalized
        }

        return DispatchQueue.main.sync {
            subjectCurrentNormalized
        }
    }

    private func readSubjectTrackScore() -> Float {
        if Thread.isMainThread {
            return subjectTrackScore
        }

        return DispatchQueue.main.sync {
            subjectTrackScore
        }
    }

    private func readSubjectIsLost() -> Bool {
        if Thread.isMainThread {
            return subjectIsLost
        }

        return DispatchQueue.main.sync {
            subjectIsLost
        }
    }

    private func readUserSubjectAnchorNormalized() -> CGPoint? {
        if DispatchQueue.getSpecific(key: sessionQueueKey) != nil {
            return userSubjectAnchorNormalized
        }

        return sessionQueue.sync {
            userSubjectAnchorNormalized
        }
    }

    private func readEffectiveSubjectAnchorNormalized() -> CGPoint {
        if DispatchQueue.getSpecific(key: sessionQueueKey) != nil {
            return effectiveSubjectAnchorNormalized
        }

        return sessionQueue.sync {
            effectiveSubjectAnchorNormalized
        }
    }

    private func readCurrentAutoFocusAnchorNormalized() -> CGPoint {
        if DispatchQueue.getSpecific(key: sessionQueueKey) != nil {
            return currentAutoFocusAnchorNormalized
        }

        return sessionQueue.sync {
            currentAutoFocusAnchorNormalized
        }
    }

    private func updateUserAnchorStateFromTracking(
        isLost: Bool,
        confidence: Float,
        trackedCenter: CGPoint?,
        now: CFTimeInterval
    ) {
        guard isUserAnchorActive else { return }
        guard let userAnchor = userSubjectAnchorNormalized else {
            userSubjectAnchorNormalized = nil
            isUserAnchorActive = false
            userAnchorSetTime = 0
            updateEffectiveAnchor()
            return
        }

        if !isLost, confidence >= userAnchorReleaseConfidence, let trackedCenter {
            let matchRadius2 = userAnchorMatchRadius * userAnchorMatchRadius
            let matched = squaredDistance(userAnchor, trackedCenter) <= matchRadius2
            if matched {
                userSubjectAnchorNormalized = nil
                isUserAnchorActive = false
                userAnchorSetTime = 0
                updateEffectiveAnchor()
                return
            }
        }

        if isLost, userAnchorSetTime > 0, (now - userAnchorSetTime) >= userAnchorLossTimeout {
            userSubjectAnchorNormalized = nil
            isUserAnchorActive = false
            userAnchorSetTime = 0
            updateEffectiveAnchor()
        }
    }

    private func squaredDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }

    private func setRawSymmetry(dx: CGFloat, dy: CGFloat, strength: CGFloat, confidence: CGFloat) {
        DispatchQueue.main.async {
            self.rawSymmetryDx = dx
            self.rawSymmetryDy = dy
            self.rawSymmetryStrength = strength
            self.rawSymmetryConfidence = confidence
        }
    }

    private func setStableSymmetry(dx: CGFloat, dy: CGFloat, isHolding: Bool) {
        DispatchQueue.main.async {
            self.stableSymmetryDx = dx
            self.stableSymmetryDy = dy
            self.stableSymmetryIsHolding = isHolding
        }
    }

    private func setOverlayHints(targetPoint: CGPoint?, diagonalType: DiagonalType?, negativeSpaceZone: CGRect?) {
        DispatchQueue.main.async {
            self.overlayTargetPoint = targetPoint
            self.overlayDiagonalType = diagonalType
            self.overlayNegativeSpaceZone = negativeSpaceZone
        }
    }

    private func resetTrackingResilienceState() {
        trackingResilienceController.reset()
    }

    private func publishSmartComposeState() {
        let snapshot = smartComposeController.snapshot()
        DispatchQueue.main.async {
            self.isSmartComposeActive = snapshot.isActive
            self.isSmartComposeProcessing = snapshot.isProcessing
        }
    }

    private func stopSmartCompose() {
        smartComposeController.reset()
        publishSmartComposeState()
    }

    private func updateTrackingResilience(
        trackedCenter: inout CGPoint?,
        trackedConfidence: inout Float,
        trackedIsLost: inout Bool,
        now: CFTimeInterval,
        fallbackAnchor: CGPoint
    ) {
        if let reacquirePoint = trackingResilienceController.update(
            trackedCenter: &trackedCenter,
            trackedConfidence: &trackedConfidence,
            trackedIsLost: &trackedIsLost,
            now: now,
            fallbackAnchor: fallbackAnchor
        ) {
            subjectTrackingQueue.async { [weak self] in
                self?.visionTracker.startTracking(tapPointNormalized: reacquirePoint)
            }
        }
    }

    private func buildAICoachSnapshotForSmartCompose() -> AICoachFrameSnapshot {
        let templateID = readSelectedTemplateID()
        let subject = readSubjectCurrentNormalized()
        let targetPoint: CGPoint? = {
            if Thread.isMainThread {
                return overlayTargetPoint
            }
            return DispatchQueue.main.sync { overlayTargetPoint }
        }()
        let stable: (dx: CGFloat, dy: CGFloat, confidence: CGFloat, isLost: Bool) = {
            if Thread.isMainThread {
                return (stableSymmetryDx, stableSymmetryDy, rawSymmetryConfidence, subjectIsLost)
            }
            return DispatchQueue.main.sync {
                (stableSymmetryDx, stableSymmetryDy, rawSymmetryConfidence, subjectIsLost)
            }
        }()
        let overlayHints: (diagonalType: DiagonalType?, negativeSpaceZone: CGRect?) = {
            if Thread.isMainThread {
                return (overlayDiagonalType, overlayNegativeSpaceZone)
            }
            return DispatchQueue.main.sync {
                (overlayDiagonalType, overlayNegativeSpaceZone)
            }
        }()
        let structuralTags = AICoachStructuralTagBuilder.build(input: AICoachStructuralTagInput(
            templateID: templateID,
            subjectPoint: subject,
            targetPoint: targetPoint,
            stableDx: stable.dx,
            stableDy: stable.dy,
            confidence: stable.confidence,
            diagonalType: overlayHints.diagonalType,
            negativeSpaceZone: overlayHints.negativeSpaceZone
        ))
        return AICoachFrameSnapshot(
            templateID: templateID,
            subjectX: subject.map { Double($0.x) },
            subjectY: subject.map { Double($0.y) },
            targetX: targetPoint.map { Double($0.x) },
            targetY: targetPoint.map { Double($0.y) },
            stableDx: Double(stable.dx),
            stableDy: Double(stable.dy),
            confidence: Double(stable.confidence),
            isLost: stable.isLost,
            structuralTags: structuralTags
        )
    }

    private func readCurrentUIZoomEstimate() -> CGFloat {
        readDeviceValue { [weak self] device in
            guard let self else { return nil }
            let z = CGFloat(device.videoZoomFactor)
            if self.currentPosition == .back, device.deviceType == .builtInUltraWideCamera {
                return max(0.5, min(1.0, 0.5 + (z - 1.0) * 0.5))
            }
            return max(0.5, z)
        } ?? 1.0
    }

    private func processSmartComposeOnFrame(
        now: CFTimeInterval,
        currentTemplateID: String?,
        isHolding: Bool,
        guidanceConfidence: CGFloat,
        trackedIsLost: Bool
    ) {
        if movieOutput.isRecording {
            stopSmartCompose()
            return
        }
        let decision = smartComposeController.decisionForFrame(
            now: now,
            currentTemplateID: currentTemplateID,
            isHolding: isHolding,
            guidanceConfidence: guidanceConfidence,
            trackedIsLost: trackedIsLost
        )

        if decision.shouldPublishState {
            publishSmartComposeState()
            return
        }
        guard let targetZoom = decision.targetZoom else { return }

        let currentZoom = readCurrentUIZoomEstimate()
        let delta = targetZoom - currentZoom
        if abs(delta) < 0.03 {
            stopSmartCompose()
            return
        }
        let adaptiveStep = smartComposeController.adaptiveZoomStep(for: abs(delta))
        let step = delta > 0 ? adaptiveStep : -adaptiveStep
        let nextZoom = currentZoom + step
        setZoomFactorWithinCurrentLens(nextZoom, smooth: true)
        finalizeZoom(nextZoom)
    }

    private func showTemplateSupportMessage(for id: String) {
        let supported = CompositionTemplateType.supportedTemplateIDs.sorted().joined(separator: ", ")
        let message = "Template \(id) is not implemented. Supported: \(supported)"
        let token = UUID()
        templateSupportMessageToken = token
        DispatchQueue.main.async {
            self.templateSupportMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self, self.templateSupportMessageToken == token else { return }
            self.templateSupportMessage = nil
        }
    }

    private func clearTemplateSupportMessage() {
        templateSupportMessageToken = UUID()
        DispatchQueue.main.async {
            self.templateSupportMessage = nil
        }
    }

    private func scheduleAICoachEvaluation(
        templateID: String?,
        subjectPoint: CGPoint?,
        targetPoint: CGPoint?,
        stableDx: CGFloat,
        stableDy: CGFloat,
        confidence: CGFloat,
        isLost: Bool,
        diagonalType: DiagonalType?,
        negativeSpaceZone: CGRect?,
        now: CFTimeInterval
    ) {
        guard now >= aiCoachNextAllowedTime else { return }
        guard !aiCoachInFlight else { return }
        aiCoachInFlight = true
        aiCoachNextAllowedTime = now + aiCoachInterval

        let structuralTags = AICoachStructuralTagBuilder.build(input: AICoachStructuralTagInput(
            templateID: templateID,
            subjectPoint: subjectPoint,
            targetPoint: targetPoint,
            stableDx: stableDx,
            stableDy: stableDy,
            confidence: confidence,
            diagonalType: diagonalType,
            negativeSpaceZone: negativeSpaceZone
        ))

        let snapshot = AICoachFrameSnapshot(
            templateID: templateID,
            subjectX: subjectPoint.map { Double($0.x) },
            subjectY: subjectPoint.map { Double($0.y) },
            targetX: targetPoint.map { Double($0.x) },
            targetY: targetPoint.map { Double($0.y) },
            stableDx: Double(stableDx),
            stableDy: Double(stableDy),
            confidence: Double(confidence),
            isLost: isLost,
            structuralTags: structuralTags
        )

        Task { [weak self] in
            guard let self else { return }
            let advice = await self.aiCoachCoordinator.evaluate(snapshot: snapshot)
            DispatchQueue.main.async {
                self.aiCoachInstruction = advice.instruction
                self.aiCoachScore = advice.score
                self.aiCoachShouldHold = advice.shouldHold
                self.aiCoachReason = advice.reason
                self.aiCoachSuggestedTemplateID = advice.suggestedTemplateID
                self.aiCoachSuggestedTemplateReason = advice.suggestedTemplateReason
                if let availabilityMessage = advice.availabilityMessage {
                    self.aiCoachAvailabilityMessage = availabilityMessage
                } else if advice.usedFoundationModel {
                    self.aiCoachAvailabilityMessage = nil
                }
            }
            self.videoDataOutputQueue.async { [weak self] in
                self?.aiCoachInFlight = false
            }
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

    private func updateOutputsForMode(_ mode: CaptureMode) {
        switch mode {
        case .photo:
            if session.outputs.contains(where: { $0 === movieOutput }) {
                session.removeOutput(movieOutput)
            }
        case .video:
            if !session.outputs.contains(where: { $0 === movieOutput }),
               session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }
        }
    }

    private func defaultCameraDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if position == .front {
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInTrueDepthCamera, .builtInWideAngleCamera],
                mediaType: .video,
                position: .front
            )
            return discovery.devices.first
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
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
        applyInterfaceRotation(to: connection)
        if connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .auto
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = (currentPosition == .front)
        }
    }

    private func configureVideoDataOutputConnection() {
        guard let connection = videoDataOutput.connection(with: .video) else { return }
        applyInterfaceRotation(to: connection)
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = (currentPosition == .front)
        }
    }

    private func configurePhotoOutputConnection() {
        guard let connection = photoOutput.connection(with: .video) else { return }
        applyInterfaceRotation(to: connection)
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = (currentPosition == .front)
        }
    }

    private func applyVideoConnectionsForCurrentState(position: AVCaptureDevice.Position) {
        if let connection = movieOutput.connection(with: .video) {
            applyInterfaceRotation(to: connection)
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = (position == .front)
            }
        }
        if let connection = photoOutput.connection(with: .video) {
            applyInterfaceRotation(to: connection)
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = (position == .front)
            }
        }
        if let connection = videoDataOutput.connection(with: .video) {
            applyInterfaceRotation(to: connection)
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = (position == .front)
            }
        }
    }

    private func applyInterfaceRotation(to connection: AVCaptureConnection) {
        let angle = currentInterfaceVideoRotationAngle()
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }

    private func currentInterfaceVideoRotationAngle() -> CGFloat {
        let deviceOrientation = UIDevice.current.orientation
        switch deviceOrientation {
        case .landscapeLeft:
            return 0
        case .landscapeRight:
            return 180
        case .portraitUpsideDown:
            return 270
        default:
            break
        }

        let interfaceOrientation = readCurrentInterfaceOrientation()
        switch interfaceOrientation {
        case .landscapeRight:
            return 0
        case .landscapeLeft:
            return 180
        case .portraitUpsideDown:
            return 270
        default:
            return 90
        }
    }

    private func readCurrentInterfaceOrientation() -> UIInterfaceOrientation {
        let readOrientation = { () -> UIInterfaceOrientation in
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first(where: { $0.activationState == .foregroundActive })?
                .interfaceOrientation ?? .portrait
        }
        if Thread.isMainThread {
            return readOrientation()
        }
        return DispatchQueue.main.sync {
            readOrientation()
        }
    }

    func syncConnectionsToInterfaceOrientation() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureMovieOutputConnection()
            self.configurePhotoOutputConnection()
            self.configureVideoDataOutputConnection()
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

    private func readPreviewVisibleRectNormalized() -> CGRect? {
        if Thread.isMainThread {
            return sanitizeNormalizedRect(previewVisibleRectProvider?())
        }
        return DispatchQueue.main.sync {
            sanitizeNormalizedRect(previewVisibleRectProvider?())
        }
    }

    private func storePendingPhotoCropRect(_ rect: CGRect?, for uniqueID: Int64) {
        photoCropStateQueue.sync {
            if let rect {
                pendingPhotoCropRectByID[uniqueID] = rect
            } else {
                pendingPhotoCropRectByID.removeValue(forKey: uniqueID)
            }
        }
    }

    private func consumePendingPhotoCropRect(for uniqueID: Int64) -> CGRect? {
        photoCropStateQueue.sync {
            defer { pendingPhotoCropRectByID.removeValue(forKey: uniqueID) }
            return pendingPhotoCropRectByID[uniqueID]
        }
    }

    private func sanitizeNormalizedRect(_ rect: CGRect?) -> CGRect? {
        guard let rect else { return nil }
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let normalized = rect.standardized.intersection(unit)
        guard !normalized.isNull, normalized.width > 0, normalized.height > 0 else { return nil }
        return normalized
    }

    private func needsCropping(_ normalizedRect: CGRect?) -> Bool {
        guard let rect = sanitizeNormalizedRect(normalizedRect) else { return false }
        let epsilon: CGFloat = 0.001
        return abs(rect.minX) > epsilon
            || abs(rect.minY) > epsilon
            || abs(rect.width - 1) > epsilon
            || abs(rect.height - 1) > epsilon
    }

    private func prepareRecordingOutputURL() -> URL {
        if Thread.isMainThread {
            return recordingStateController.prepareOutputURL()
        }
        return DispatchQueue.main.sync {
            recordingStateController.prepareOutputURL()
        }
    }

    private func beginRecordingUIState() {
        let applyDuration: (TimeInterval) -> Void = { [weak self] duration in
            self?.recordingDuration = duration
        }

        let updateState = { [weak self] in
            guard let self else { return }
            self.isRecording = true
            self.recordingStateController.begin(onDurationChange: applyDuration)
        }

        if Thread.isMainThread {
            updateState()
        } else {
            DispatchQueue.main.async(execute: updateState)
        }
    }

    private func finishRecordingUIState() -> UUID? {
        let applyDuration: (TimeInterval) -> Void = { [weak self] duration in
            self?.recordingDuration = duration
        }

        let updateState = { () -> UUID? in
            self.isRecording = false
            return self.recordingStateController.finish(onDurationChange: applyDuration)
        }

        if Thread.isMainThread {
            return updateState()
        }
        return DispatchQueue.main.sync(execute: updateState)
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
        let cropRect = consumePendingPhotoCropRect(for: photo.resolvedSettings.uniqueID)

        if error != nil {
            setCaptureResult(success: false, message: "Capture failed")
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            setCaptureResult(success: false, message: "Capture failed")
            return
        }

        let settings = currentFilterSettings()
        let applyFilters = isFilterActive(settings)
        let applyCrop = needsCropping(cropRect)
        let outputData: Data
        if (applyFilters || applyCrop),
           let processed = CapturedPhotoProcessor.process(
               data,
               settings: settings,
               applyFilters: applyFilters,
               cropRectNormalized: applyCrop ? cropRect : nil,
               ciContext: ciContext
           ) {
            outputData = processed
        } else {
            outputData = data
        }

        Task {
            do {
                try await mediaLibrary.savePhoto(outputData)
                setCaptureResult(success: true, message: nil)
            } catch {
                setCaptureResult(success: false, message: "Save failed")
            }
        }
    }
}

extension CameraSessionController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let finishedRecordingID = finishRecordingUIState()

        if let error {
            setCaptureResult(success: false, message: error.localizedDescription)
            return
        }

        guard let id = finishedRecordingID else {
            setCaptureResult(success: false, message: "Save failed")
            return
        }

        Task {
            await logRecordedVideoMetadata(url: outputFileURL)
            do {
                try await mediaLibrary.saveVideoFile(at: outputFileURL, id: id)
                setCaptureResult(success: true, message: nil)
            } catch {
                setCaptureResult(success: false, message: "Save failed")
            }
        }
    }

    private func logRecordedVideoMetadata(url: URL) async {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .video),
              let track = tracks.first else {
            print("Video metadata: no video track")
            return
        }
        guard let natural = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform) else {
            print("Video metadata: failed to load track properties")
            return
        }
        let displayRect = CGRect(origin: .zero, size: natural).applying(transform)
        let displaySize = CGSize(width: abs(displayRect.width), height: abs(displayRect.height))
        print("Video metadata: natural=\(natural) transform=\(transform) display=\(displaySize)")
    }

}

extension CameraSessionController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        let templateID = readSelectedTemplateID()
        let template = CompositionTemplateType(id: templateID)

        var trackedCenter: CGPoint? = nil
        var trackedConfidence: Float = 0
        var trackedIsLost: Bool = true
        var faceObservation: FaceSubjectObservation? = nil

        subjectTrackingQueue.sync {
            self.latestSampleBuffer = sampleBuffer
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            let result = self.visionTracker.update(pixelBuffer: pixelBuffer)
            trackedCenter = result.center
            trackedConfidence = result.confidence
            trackedIsLost = result.isLost
            if template == .portraitHeadroom {
                faceObservation = self.faceSubjectAnalyzer.update(sampleBuffer: sampleBuffer, now: now)
            }
        }

        sessionQueue.sync {
            guard self.isUserAnchorActive,
                  let userAnchor = self.userSubjectAnchorNormalized,
                  let center = trackedCenter else {
                return
            }
            let matchRadius2 = self.userAnchorMatchRadius * self.userAnchorMatchRadius
            if self.squaredDistance(userAnchor, center) > matchRadius2 {
                // Ignore mismatched tracker center and keep using tap anchor.
                trackedCenter = nil
                trackedConfidence = 0
                trackedIsLost = true
            }
        }

        let rawTrackedCenter = trackedCenter
        let rawTrackedConfidence = trackedConfidence
        let rawTrackedIsLost = trackedIsLost
        let resilienceFallbackAnchor = readEffectiveSubjectAnchorNormalized()
        updateTrackingResilience(
            trackedCenter: &trackedCenter,
            trackedConfidence: &trackedConfidence,
            trackedIsLost: &trackedIsLost,
            now: now,
            fallbackAnchor: resilienceFallbackAnchor
        )

        var anchorForCompute = CGPoint(x: 0.5, y: 0.5)
        var userAnchorForCompute: CGPoint? = nil
        var autoAnchorForCompute = CGPoint(x: 0.5, y: 0.5)
        sessionQueue.sync {
            self.updateUserAnchorStateFromTracking(
                isLost: rawTrackedIsLost,
                confidence: rawTrackedConfidence,
                trackedCenter: rawTrackedCenter,
                now: now
            )
            anchorForCompute = self.effectiveSubjectAnchorNormalized
            userAnchorForCompute = self.userSubjectAnchorNormalized
            autoAnchorForCompute = self.currentAutoFocusAnchorNormalized
        }

        let trackedCenterSnapshot = trackedCenter
        let trackedConfidenceSnapshot = trackedConfidence
        let trackedIsLostSnapshot = trackedIsLost
        DispatchQueue.main.async {
            self.subjectCurrentNormalized = trackedCenterSnapshot
            self.subjectTrackScore = trackedConfidenceSnapshot
            self.subjectIsLost = trackedIsLostSnapshot
        }

        var aiTemplateID: String? = nil
        var aiTargetPoint: CGPoint? = nil
        var aiDiagonalType: DiagonalType? = nil
        var aiNegativeSpaceZone: CGRect? = nil
        var aiStableDx: CGFloat = 0
        var aiStableDy: CGFloat = 0
        var aiConfidence: CGFloat = 0
        var isHoldingForSmartCompose: Bool = true
        if template != .other {
            let guidance = frameGuidanceCoordinator.evaluate(
                sampleBuffer: sampleBuffer,
                template: template,
                anchorNormalized: anchorForCompute,
                subjectCurrentNormalized: trackedCenter,
                subjectTrackConfidence: trackedConfidence,
                subjectIsLost: trackedIsLost,
                faceObservation: faceObservation,
                userSubjectAnchorNormalized: userAnchorForCompute,
                autoFocusAnchorNormalized: autoAnchorForCompute,
                now: now
            )
            setRawSymmetry(
                dx: guidance.rawDx,
                dy: guidance.rawDy,
                strength: guidance.rawStrength,
                confidence: guidance.rawConfidence
            )
            setOverlayHints(
                targetPoint: guidance.targetPoint,
                diagonalType: guidance.diagonalType,
                negativeSpaceZone: guidance.negativeSpaceZone
            )
            setStableSymmetry(
                dx: guidance.stableDx,
                dy: guidance.stableDy,
                isHolding: guidance.isHolding
            )
            isHoldingForSmartCompose = guidance.isHolding
            aiTemplateID = guidance.canonicalTemplateID
            aiTargetPoint = guidance.targetPoint
            aiDiagonalType = guidance.diagonalType
            aiNegativeSpaceZone = guidance.negativeSpaceZone
            aiStableDx = guidance.stableDx
            aiStableDy = guidance.stableDy
            aiConfidence = guidance.rawConfidence
        } else {
            setRawSymmetry(dx: 0, dy: 0, strength: 0, confidence: 0)
            setOverlayHints(targetPoint: nil, diagonalType: nil, negativeSpaceZone: nil)
            frameGuidanceCoordinator.reset()
            setStableSymmetry(dx: 0, dy: 0, isHolding: true)
            isHoldingForSmartCompose = true
        }
        processSmartComposeOnFrame(
            now: now,
            currentTemplateID: aiTemplateID,
            isHolding: isHoldingForSmartCompose,
            guidanceConfidence: aiConfidence,
            trackedIsLost: trackedIsLost
        )
        scheduleAICoachEvaluation(
            templateID: aiTemplateID,
            subjectPoint: trackedCenter,
            targetPoint: aiTargetPoint,
            stableDx: aiStableDx,
            stableDy: aiStableDy,
            confidence: aiConfidence,
            isLost: trackedIsLost,
            diagonalType: aiDiagonalType,
            negativeSpaceZone: aiNegativeSpaceZone,
            now: now
        )

        guard isFilterPreviewActive else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let settings = currentFilterSettings()
        guard isFilterActive(settings) else { return }

        guard let cgImage = LiveFilterPreviewRenderer.render(
            pixelBuffer: pixelBuffer,
            settings: settings,
            ciContext: ciContext
        ) else { return }

        DispatchQueue.main.async { [weak self] in
            self?.filteredPreviewImage = cgImage
        }
    }
}

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// 取景区域
struct ViewfinderView: View {
    // 相机会话控制器（权限 + 会话管理）
    @ObservedObject var cameraController: CameraSessionController
    var selectedTemplate: String?
    var usePadPortraitLayout: Bool
    var usePadLandscapeLayout: Bool
    var guidanceUIMode: DebugSettings.GuidanceUIMode
    var showGuidanceDebugHUD: Bool
    var showAICoachDebugHUD: Bool

    @EnvironmentObject private var debugSettings: DebugSettings

    // 当前缩放值（双指捏合实时更新）
    @State private var zoomValue: CGFloat = 1.0
    // 基准缩放值（用于累计多次捏合）
    @State private var baseZoom: CGFloat = 1.0
    // 缩放提示胶囊显示控制
    @State private var showZoomBadge: Bool = false

    // 点击对焦提示
    @State private var focusPoint: CGPoint = .zero
    @State private var showFocusIndicator: Bool = false
    @State private var didFireHoldHaptic: Bool = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // 中间区域用黑色作为留白背景（letterboxing）
                Color.black

                // 4:3 取景区域，宽度与屏幕一致（更接近原生相机观感）
                let desiredTopGap: CGFloat = usePadPortraitLayout ? 8 : 14
                let maxContainerWidth = proxy.size.width
                let maxContainerHeight = proxy.size.height
                let viewfinderWidth: CGFloat = {
                    if usePadLandscapeLayout {
                        return maxContainerWidth
                    }
                    if usePadPortraitLayout {
                        // iPad portrait: keep 4:3 inside available bounds.
                        let maxWidthByHeight = maxContainerHeight * 3.0 / 4.0
                        return min(maxContainerWidth, maxWidthByHeight)
                    }
                    // iPhone path remains unchanged.
                    return maxContainerWidth
                }()
                let viewfinderHeight: CGFloat = {
                    if usePadLandscapeLayout {
                        return maxContainerHeight
                    }
                    return viewfinderWidth * 4.0 / 3.0
                }()
                let remainingHeight = max(0, maxContainerHeight - viewfinderHeight)
                // 在居中基础上增加固定顶部间距，确保与 TopBar 有明确分离
                let topGap = usePadLandscapeLayout ? 0 : min(remainingHeight, remainingHeight * 0.5 + desiredTopGap)
                let bottomGap = max(0, remainingHeight - topGap)

                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: topGap)

                    ZStack {
                        let isSmartComposeThinking = cameraController.isSmartComposeProcessing

                        // 相机预览层（授权后显示真实画面）
                        if cameraController.state == .authorized || cameraController.state == .running {
                            CameraPreviewView(
                                session: cameraController.session,
                                isFrontCamera: cameraController.cameraPosition == .front,
                                previewFreeze: cameraController.previewFreeze,
                                onPreviewView: { view in
                                    cameraController.snapshotProvider = { [weak view] in
                                        view?.snapshotImage()
                                    }
                                    cameraController.previewVisibleRectProvider = { [weak view] in
                                        view?.visibleMetadataOutputRect()
                                    }
                                }
                            )
                            .modifier(LivePreviewCropModifier(
                                cameraPosition: cameraController.cameraPosition,
                                captureMode: cameraController.captureMode
                            ))
                            .saturation(isSmartComposeThinking ? 0.85 : 1.0)
                            .blur(radius: isSmartComposeThinking ? 10 : 0)
                            .animation(.easeInOut(duration: 0.25), value: isSmartComposeThinking)

                            FilteredPreviewOverlayView(cameraController: cameraController)
                                .modifier(LivePreviewCropModifier(
                                    cameraPosition: cameraController.cameraPosition,
                                    captureMode: cameraController.captureMode
                                ))
                                .saturation(isSmartComposeThinking ? 0.85 : 1.0)
                                .blur(radius: isSmartComposeThinking ? 10 : 0)
                                .animation(.easeInOut(duration: 0.25), value: isSmartComposeThinking)
                                .allowsHitTesting(false)
                        } else {
                            Color.black
                        }

                        let cameraMoveOffset: CGSize = {
                            guard selectedTemplate != nil else {
                                return .zero
                            }
                            let rawOffset = CGSize(
                                width: cameraController.rawSymmetryDx,
                                height: cameraController.rawSymmetryDy
                            )
                            let stableOffset = CGSize(
                                width: cameraController.stableSymmetryDx,
                                height: cameraController.stableSymmetryDy
                            )
                            let subjectOffset = directionalStableOffset(
                                raw: rawOffset,
                                stable: stableOffset
                            )
                            return CGSize(
                                width: -subjectOffset.width,
                                height: -subjectOffset.height
                            )
                        }()
                        let coachedOffset = coachAugmentedOffset(
                            baseOffset: cameraMoveOffset,
                            score: cameraController.aiCoachScore,
                            shouldHold: cameraController.aiCoachShouldHold,
                            instruction: cameraController.aiCoachInstruction
                        )

                        if !isSmartComposeThinking, let selectedTemplate {
                            TemplateOverlayView(
                                model: TemplateOverlayModel(
                                    templateId: selectedTemplate,
                                    strength: cameraController.rawSymmetryStrength,
                                    targetPoint: cameraController.overlayTargetPoint,
                                    diagonalType: cameraController.overlayDiagonalType,
                                    negativeSpaceZone: cameraController.overlayNegativeSpaceZone
                                )
                            )
                                .allowsHitTesting(false)

                            switch guidanceUIMode {
                            case .moving:
                                GuidanceLayeredDotHUDView(
                                    guidanceOffset: coachedOffset,
                                    strength: cameraController.rawSymmetryStrength,
                                    isHolding: cameraController.stableSymmetryIsHolding || cameraController.aiCoachShouldHold
                                )
                            case .arrow:
                                ArrowGuidanceHUDView(
                                    guidanceOffset: coachedOffset,
                                    strength: cameraController.rawSymmetryStrength,
                                    isHolding: cameraController.stableSymmetryIsHolding || cameraController.aiCoachShouldHold
                                )
                            case .arrowScope:
                                ArrowGuidanceHUDView(
                                    guidanceOffset: coachedOffset,
                                    strength: cameraController.rawSymmetryStrength,
                                    isHolding: cameraController.stableSymmetryIsHolding || cameraController.aiCoachShouldHold,
                                    crosshairStyle: .scope
                                )
                            }
                        }

                        if showGuidanceDebugHUD {
                            GuidanceDebugHUDView(
                                selectedTemplate: selectedTemplate,
                                guidanceUIMode: guidanceUIMode,
                                rawDx: cameraController.rawSymmetryDx,
                                rawDy: cameraController.rawSymmetryDy,
                                rawStrength: cameraController.rawSymmetryStrength,
                                rawConfidence: cameraController.rawSymmetryConfidence,
                                stableDx: cameraController.stableSymmetryDx,
                                stableDy: cameraController.stableSymmetryDy,
                                isHolding: cameraController.stableSymmetryIsHolding,
                                subjectCurrentNormalized: cameraController.subjectCurrentNormalized,
                                subjectTrackScore: cameraController.subjectTrackScore,
                                subjectIsLost: cameraController.subjectIsLost,
                                effectiveAnchorNormalized: cameraController.effectiveAnchorNormalized,
                                userAnchorNormalized: cameraController.userSubjectAnchorNormalized,
                                autoFocusAnchorNormalized: cameraController.currentAutoFocusAnchorNormalized,
                                uiDx: coachedOffset.width,
                                uiDy: coachedOffset.height
                            )
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .allowsHitTesting(false)
                        }

                        if showAICoachDebugHUD {
                            AICoachDebugHUDView(
                                smartComposeActive: cameraController.isSmartComposeActive,
                                smartComposeProcessing: cameraController.isSmartComposeProcessing,
                                score: cameraController.aiCoachScore,
                                shouldHold: cameraController.aiCoachShouldHold,
                                instruction: cameraController.aiCoachInstruction,
                                reason: cameraController.aiCoachReason,
                                suggestedTemplateID: cameraController.aiCoachSuggestedTemplateID,
                                suggestedTemplateReason: cameraController.aiCoachSuggestedTemplateReason,
                                availabilityMessage: cameraController.aiCoachAvailabilityMessage
                            )
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .allowsHitTesting(false)
                        }

                        if let message = cameraController.templateSupportMessage {
                            Text(message)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.82))
                                .clipShape(Capsule(style: .continuous))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .padding(.top, 8)
                                .padding(.horizontal, 12)
                                .allowsHitTesting(false)
                        }

                        if cameraController.isCameraSwitching, let snapshot = cameraController.switchSnapshot {
                            Image(uiImage: snapshot)
                                .resizable()
                                .scaledToFill()
                                .transition(.opacity)
                                .clipped()
                                .allowsHitTesting(false)
                        } else if cameraController.isModeSwitching || cameraController.isCameraSwitching {
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .overlay(Color.black.opacity(0.15))
                                .transition(.opacity)
                                .allowsHitTesting(false)
                        }

                        // 三等分网格线，可用于构图
                        if debugSettings.showGridOverlay && selectedTemplate == nil {
                            GridOverlayView()
                                .padding(1)
                        }

                        LevelOverlay(isEnabled: cameraController.isLevelOverlayEnabled)
                            .padding(1)

                        // 未授权或不可用时提示文本
                        if cameraController.state == .denied || cameraController.state == .unavailable {
                            VStack(spacing: 6) {
                                Text("Camera access required")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)

                                #if targetEnvironment(simulator)
                                if cameraController.state == .unavailable {
                                    Text("Running on Simulator")
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                #endif
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.7))
                            .clipShape(Capsule(style: .continuous))
                        }

                        // 录制中提示
                        if cameraController.isRecording {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 6, height: 6)
                                Text("REC")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.red)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.7))
                            .clipShape(Capsule(style: .continuous))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(.top, 10)
                            .padding(.leading, 10)
                        }

                        VStack {
                            if cameraController.captureMode == .video && cameraController.isRecording {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 8, height: 8)
                                    Text(cameraController.recordingDurationText)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.red)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 12)
                            }
                            Spacer()
                        }

                        // 拍照/保存出错提示
                        if let message = cameraController.lastErrorMessage,
                           cameraController.state == .running || cameraController.state == .authorized {
                            Text(message)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.7))
                                .clipShape(Capsule(style: .continuous))
                                .padding(.bottom, 10)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }

                        // 快门黑闪（只覆盖取景框）
                        Rectangle()
                            .fill(Color.black)
                            .opacity(cameraController.isShutterFlashing ? 1.0 : 0.0)
                            .animation(.easeInOut(duration: 0.08), value: cameraController.isShutterFlashing)

                        // 点击对焦提示框
                        if showFocusIndicator {
                            let focusIndicatorSize: CGFloat = usePadPortraitLayout ? 84 : 70
                            Circle()
                                .stroke(Color.yellow.opacity(0.9), lineWidth: 2)
                                .frame(width: focusIndicatorSize, height: focusIndicatorSize)
                                .position(focusPoint)
                                .transition(.opacity)
                        }
                    }
                    .frame(width: viewfinderWidth, height: viewfinderHeight)
                    .clipped()
                    // 捏合时显示当前倍率提示
                    .overlay(alignment: .top) {
                        if showZoomBadge {
                            Text(formattedZoom(zoomValue))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.7))
                                .clipShape(Capsule(style: .continuous))
                                .padding(.top, 10)
                                .transition(.opacity)
                        }
                    }
                    .overlay {
                        if cameraController.isSmartComposeActive || cameraController.isSmartComposeProcessing {
                            SmartComposeEdgeAuraView(isProcessing: cameraController.isSmartComposeProcessing)
                                .padding(2)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay {
                        if cameraController.isSmartComposeProcessing {
                            SmartComposeWaveSweepView()
                                .allowsHitTesting(false)
                        }
                    }
                    // 点击对焦（获取点击位置）
                    .overlay {
                        GeometryReader { geo in
                            Color.clear
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onEnded { value in
                                            let size = geo.size
                                            let location = value.location
                                            let normalized = CGPoint(
                                                x: clamp(location.x / size.width, min: 0, max: 1),
                                                y: clamp(location.y / size.height, min: 0, max: 1)
                                            )

                                            focusPoint = location
                                            showFocusIndicator = true
                                            withAnimation(.easeOut(duration: 0.25)) {
                                                showFocusIndicator = true
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                                withAnimation(.easeOut(duration: 0.2)) {
                                                    showFocusIndicator = false
                                                }
                                            }

                                            cameraController.focus(at: normalized)
                                        }
                                )
                        }
                    }
                    // 双指捏合缩放（无 UI 控件）
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                showZoomBadge = true
                                let updated = baseZoom * value
                                let minZoom = cameraController.minUIZoom
                                zoomValue = clamp(updated, min: minZoom, max: 8.0)
                                cameraController.setZoomFactorWithinCurrentLens(zoomValue, smooth: true)
                            }
                            .onEnded { _ in
                                let minZoom = cameraController.minUIZoom
                                zoomValue = clamp(zoomValue, min: minZoom, max: 8.0)
                                baseZoom = zoomValue
                                cameraController.finalizeZoom(zoomValue)
                                withAnimation(.easeOut(duration: 0.25)) {
                                    showZoomBadge = false
                                }
                            }
                    )

                    Color.clear
                        .frame(height: bottomGap)
                }
                .frame(width: maxContainerWidth, height: maxContainerHeight)
            }
            .onAppear {
                UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            }
            .task {
                await cameraController.requestAuthorizationIfNeeded()
                cameraController.configureIfNeeded()
                cameraController.startSession()
                cameraController.syncConnectionsToInterfaceOrientation()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                cameraController.syncConnectionsToInterfaceOrientation()
            }
            .onDisappear {
                UIDevice.current.endGeneratingDeviceOrientationNotifications()
                cameraController.snapshotProvider = nil
                cameraController.previewVisibleRectProvider = nil
                cameraController.stopSession()
            }
        }
        .onChange(of: cameraController.stableSymmetryIsHolding) { _, holding in
            guard selectedTemplate != nil else {
                didFireHoldHaptic = false
                return
            }
            if holding {
                guard didFireHoldHaptic == false else { return }
                triggerHoldHaptic()
                didFireHoldHaptic = true
            } else {
                didFireHoldHaptic = false
            }
        }
        .onChange(of: selectedTemplate) { _, template in
            if template == nil {
                didFireHoldHaptic = false
            }
        }
    }

    private func triggerHoldHaptic() {
        #if canImport(UIKit)
        let feedback = UINotificationFeedbackGenerator()
        feedback.prepare()
        feedback.notificationOccurred(.success)
        #endif
    }

    // 缩放文本格式化
    private func formattedZoom(_ value: CGFloat) -> String {
        if abs(value - 1.0) < 0.05 {
            return "1x"
        }
        return String(format: "%.1fx", value)
    }

    private func directionalStableOffset(
        raw: CGSize,
        stable: CGSize,
        epsilon: CGFloat = 0.02
    ) -> CGSize {
        let rawMag = sqrt(raw.width * raw.width + raw.height * raw.height)
        let stableMag = sqrt(stable.width * stable.width + stable.height * stable.height)
        if rawMag < epsilon {
            return stable
        }
        let dirX = raw.width / rawMag
        let dirY = raw.height / rawMag
        let magnitude = max(stableMag, min(1, rawMag))
        return CGSize(width: dirX * magnitude, height: dirY * magnitude)
    }

    private func coachAugmentedOffset(
        baseOffset: CGSize,
        score: Int,
        shouldHold: Bool,
        instruction: String
    ) -> CGSize {
        if shouldHold {
            return .zero
        }
        let clampedScore = clamp(CGFloat(score), min: 0, max: 100)
        let urgency = 1 - (clampedScore / 100)
        let gain = 1.0 + urgency * 0.35
        var dx = baseOffset.width * gain
        var dy = baseOffset.height * gain

        let aiNudge = instructionNudge(from: instruction, urgency: urgency)
        dx += aiNudge.width
        dy += aiNudge.height
        return CGSize(
            width: clamp(dx, min: -1, max: 1),
            height: clamp(dy, min: -1, max: 1)
        )
    }

    private func instructionNudge(from instruction: String, urgency: CGFloat) -> CGSize {
        let text = instruction.lowercased()
        let nudge = max(0.04, 0.18 * urgency)
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if text.contains("left") {
            dx -= nudge
        }
        if text.contains("right") {
            dx += nudge
        }
        if text.contains("up") {
            dy -= nudge
        }
        if text.contains("down") {
            dy += nudge
        }
        return CGSize(width: dx, height: dy)
    }

    // 数值夹取
    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(value, max))
    }
}

private struct SmartComposeEdgeAuraView: View {
    let isProcessing: Bool

    private let auraCornerRadius: CGFloat = 14

    @State private var sweepPhase: CGFloat = -1.1
    @State private var rotation: Double = 0
    @State private var pulse: CGFloat = 0.62

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: auraCornerRadius, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        colors: [
                            Color(red: 0.28, green: 0.89, blue: 1.0),
                            Color(red: 0.44, green: 1.0, blue: 0.78),
                            Color(red: 1.0, green: 0.89, blue: 0.38),
                            Color(red: 1.0, green: 0.49, blue: 0.72),
                            Color(red: 0.65, green: 0.58, blue: 1.0),
                            Color(red: 0.28, green: 0.89, blue: 1.0)
                        ],
                        center: .center,
                        angle: .degrees(rotation)
                    ),
                    lineWidth: 3.4
                )
                .blendMode(.screen)

            RoundedRectangle(cornerRadius: auraCornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color(red: 0.28, green: 0.89, blue: 1.0).opacity(0.92),
                            Color(red: 0.44, green: 1.0, blue: 0.78).opacity(0.92),
                            Color(red: 1.0, green: 0.89, blue: 0.38).opacity(0.90),
                            Color(red: 1.0, green: 0.49, blue: 0.72).opacity(0.92),
                            Color.clear
                        ],
                        startPoint: UnitPoint(x: sweepPhase, y: 0),
                        endPoint: UnitPoint(x: sweepPhase + 1.15, y: 1)
                    ),
                    lineWidth: 7.2
                )
                .blur(radius: isProcessing ? 3.6 : 2.8)
                .opacity((isProcessing ? 0.98 : 0.68) * pulse)

            RoundedRectangle(cornerRadius: auraCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(isProcessing ? 0.22 : 0.13), lineWidth: 1.1)
        }
        .compositingGroup()
        .shadow(
            color: Color(red: 0.28, green: 0.89, blue: 1.0).opacity((isProcessing ? 0.45 : 0.28) * pulse),
            radius: isProcessing ? 11 : 8,
            x: 0,
            y: 0
        )
        .shadow(
            color: Color(red: 1.0, green: 0.49, blue: 0.72).opacity((isProcessing ? 0.38 : 0.24) * pulse),
            radius: isProcessing ? 14 : 10,
            x: 0,
            y: 0
        )
        .onAppear {
            sweepPhase = -1.1
            rotation = 0
            pulse = isProcessing ? 0.8 : 0.62

            withAnimation(.linear(duration: isProcessing ? 1.1 : 1.8).repeatForever(autoreverses: false)) {
                sweepPhase = 1.2
            }

            withAnimation(.linear(duration: isProcessing ? 3.8 : 6.5).repeatForever(autoreverses: false)) {
                rotation = 360
            }

            withAnimation(.easeInOut(duration: isProcessing ? 0.75 : 1.3).repeatForever(autoreverses: true)) {
                pulse = 1.0
            }
        }
        .transition(.opacity)
    }
}

private struct SmartComposeWaveSweepView: View {
    @State private var sweepPhase: CGFloat = 1.25
    @State private var veilOpacity: CGFloat = 0.30

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(veilOpacity)

                Rectangle()
                    .fill(Color.black.opacity(0.16))

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color(red: 0.27, green: 0.88, blue: 1.0).opacity(0.76),
                                Color(red: 0.43, green: 1.0, blue: 0.76).opacity(0.80),
                                Color(red: 1.0, green: 0.88, blue: 0.38).opacity(0.75),
                                Color(red: 1.0, green: 0.45, blue: 0.70).opacity(0.76),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * 0.32, height: proxy.size.height * 0.98)
                    .offset(x: sweepPhase * proxy.size.width)
                    .blur(radius: 10)
                    .blendMode(.screen)
                    .opacity(0.82)

                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .frame(width: proxy.size.width * 0.07, height: proxy.size.height * 0.82)
                    .offset(x: sweepPhase * proxy.size.width * 0.9)
                    .blur(radius: 5)
                    .blendMode(.screen)
            }
            .clipped()
            .onAppear {
                sweepPhase = 1.25
                veilOpacity = 0.30
                withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                    sweepPhase = -1.25
                }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    veilOpacity = 0.36
                }
            }
            .transition(.opacity)
        }
    }
}

import SwiftUI
import AVFoundation

// 取景区域
struct ViewfinderView: View {
    // 相机会话控制器（权限 + 会话管理）
    @ObservedObject var cameraController: CameraSessionController
    var selectedTemplate: String?
    var guidanceUIMode: DebugSettings.GuidanceUIMode
    var showDebugHUD: Bool

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
    @State private var previewConnection: AVCaptureConnection? = nil
    @State private var previewViewRef: PreviewView? = nil

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // 中间区域用黑色作为留白背景（letterboxing）
                Color.black

                // 4:3 取景区域居中显示
                let viewfinderWidth = proxy.size.width
                let viewfinderHeight = proxy.size.width * 4.0 / 3.0

                VStack(spacing: 0) {
                    Spacer()

                    ZStack {
                        // 相机预览层（授权后显示真实画面）
                        if cameraController.state == .authorized || cameraController.state == .running {
                            CameraPreviewView(
                                session: cameraController.session,
                                isFrontCamera: cameraController.cameraPosition == .front,
                                previewFreeze: cameraController.previewFreeze,
                                connection: $previewConnection,
                                onPreviewView: { view in
                                    Task { @MainActor in
                                        await Task.yield()
                                        previewViewRef = view
                                    }
                                }
                            )
                            .modifier(LivePreviewCropModifier(
                                cameraPosition: cameraController.cameraPosition,
                                captureMode: cameraController.captureMode
                            ))

                            FilteredPreviewOverlayView(cameraController: cameraController)
                                .modifier(LivePreviewCropModifier(
                                    cameraPosition: cameraController.cameraPosition,
                                    captureMode: cameraController.captureMode
                                ))
                                .allowsHitTesting(false)
                        } else {
                            Color.black
                        }

                        if let selectedTemplate {
                            let subjectOffset = CGSize(
                                width: cameraController.stableSymmetryDx,
                                height: cameraController.stableSymmetryDy
                            )
                            CompositionDiagramView(templateID: selectedTemplate)
                                .stroke(Color.white.opacity(0.22), lineWidth: 1)
                                .allowsHitTesting(false)

                            switch guidanceUIMode {
                            case .moving:
                                GuidanceLayeredDotHUDView(
                                    guidanceOffset: subjectOffset,
                                    strength: cameraController.rawSymmetryStrength,
                                    isHolding: cameraController.stableSymmetryIsHolding
                                )
                            case .arrow:
                                ArrowGuidanceHUDView(
                                    guidanceOffset: subjectOffset,
                                    strength: cameraController.rawSymmetryStrength,
                                    isHolding: cameraController.stableSymmetryIsHolding
                                )
                            }
                        }

                        if showDebugHUD {
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
                                subjectIsLost: cameraController.subjectIsLost
                            )
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                            Circle()
                                .stroke(Color.yellow.opacity(0.9), lineWidth: 2)
                                .frame(width: 70, height: 70)
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
                                cameraController.setZoomFactorWithinCurrentLens(zoomValue)
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

                    Spacer()
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .onAppear {
                cameraController.onPreviewConnectionUpdate = { position in
                    guard let connection = previewConnection else { return }
                    if connection.isVideoOrientationSupported {
                        connection.videoOrientation = .portrait
                    }
                    if connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = (position == .front)
                    }
                }
                cameraController.snapshotProvider = { [weak previewViewRef] in
                    previewViewRef?.snapshotImage()
                }
            }
            .task {
                await cameraController.requestAuthorizationIfNeeded()
                cameraController.configureIfNeeded()
                cameraController.startSession()
            }
            .onDisappear {
                cameraController.onPreviewConnectionUpdate = nil
                cameraController.snapshotProvider = nil
                cameraController.stopSession()
            }
        }
    }

    // 缩放文本格式化
    private func formattedZoom(_ value: CGFloat) -> String {
        if abs(value - 1.0) < 0.05 {
            return "1x"
        }
        return String(format: "%.1fx", value)
    }

    // 数值夹取
    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(value, max))
    }
}


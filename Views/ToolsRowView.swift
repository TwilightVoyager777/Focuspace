import SwiftUI
import QuartzCore
import UIKit

// 底部工具条（C1）
struct BottomC1ToolsRowView: View {
    @ObservedObject var cameraController: CameraSessionController

    enum ActiveTool {
        case none
        case wb
        case iso
        case shutter
        case ev
        case sharpness
        case contrast
        case saturation
    }

    @State private var activeTool: ActiveTool = .none
    @State private var rulerValue: Double = 0
    @State private var lastCommitTime: CFTimeInterval = 0
    @State private var autoSelection: [ActiveTool: Bool] = [:]
    @State private var levelOn: Bool = false
    @State private var colorOff: Bool = false
    @State private var sharpness: Double = 0
    @State private var contrast: Double = 1
    @State private var saturation: Double = 1

    // 工具列表
    private var items: [ToolItem] {
        let levelEnabled = LevelOverlay.isSupported
        let isVideoMode = cameraController.captureMode == .video
        var list: [ToolItem] = [
            ToolItem(title: "前置", systemName: "camera.rotate"),
            ToolItem(title: "白平衡", systemName: "circle.lefthalf.filled"),
            ToolItem(title: "感光", systemName: "sun.max"),
            ToolItem(title: "快门速度", systemName: "timer"),
            ToolItem(title: "曝光", systemName: "circle.dashed")
        ]

        if !isVideoMode {
            list.append(contentsOf: [
                ToolItem(title: "饱和度", systemName: "drop.fill"),
                ToolItem(title: "对比度", systemName: "circle.righthalf.filled"),
                ToolItem(title: "锐度", systemName: "camera.filters"),
                ToolItem(title: "色彩取消", systemName: "circle.slash")
            ])
        }

        list.append(contentsOf: [
            ToolItem(title: "水平仪", systemName: "ruler", isEnabled: levelEnabled)
        ])

        return list
    }

    // 默认高亮项
    private let selectedTitle: String = "感光"

    var body: some View {
        ZStack {
            toolsRow
                .opacity(activeTool == .none ? 1 : 0)
                .allowsHitTesting(activeTool == .none)

            if activeTool != .none {
                RulerControl(
                    title: activeToolTitle,
                    valueText: formattedRulerValue(),
                    value: $rulerValue,
                    normalizedValue: { value in
                        normalizedValue(for: activeTool, value: value)
                    },
                    valueFromNormalized: { normalized in
                        valueFromNormalized(for: activeTool, normalized: normalized)
                    },
                    clampAndStep: { value in
                        clampAndStep(value, for: activeTool)
                    },
                    autoSelectedFlag: autoSelection[activeTool] ?? false,
                    onAutoSelectedChange: { isSelected in
                        autoSelection[activeTool] = isSelected
                    },
                    onManualChange: {
                        autoSelection[activeTool] = false
                    },
                    onRequestAutoValue: { completion in
                        requestAutoValue(completion: completion)
                    },
                    onAuto: {
                        setAutoForActiveTool()
                    },
                    onDone: {
                        activeTool = .none
                    }
                )
            }
        }
        .onChange(of: activeTool) { newValue in
            rulerValue = initialRulerValue(for: newValue)
        }
        .onChange(of: rulerValue) { newValue in
            applyRulerValueIfNeeded(newValue)
        }
        .onChange(of: cameraController.captureMode) { newValue in
            if newValue == .video {
                if activeTool == .sharpness || activeTool == .contrast || activeTool == .saturation {
                    activeTool = .none
                }
            }
        }
    }

    private var toolsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(items) { item in
                    ToolButtonView(
                        title: item.title,
                        systemName: item.systemName,
                        isSelected: isItemSelected(item),
                        isEnabled: item.isEnabled,
                        action: {
                            handleTap(for: item.title)
                        }
                    )
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func isItemSelected(_ item: ToolItem) -> Bool {
        switch item.title {
        case "水平仪":
            return levelOn
        case "色彩取消":
            return colorOff
        case "白平衡":
            return activeTool == .wb
        case "感光":
            return activeTool == .iso
        case "快门速度":
            return activeTool == .shutter
        case "曝光":
            return activeTool == .ev
        case "锐度":
            return activeTool == .sharpness
        case "对比度":
            return activeTool == .contrast
        case "饱和度":
            return activeTool == .saturation
        default:
            return item.title == selectedTitle
        }
    }

    private func handleTap(for title: String) {
        switch title {
        case "前置":
            cameraController.switchCamera()
        case "水平仪":
            levelOn.toggle()
            cameraController.isLevelOverlayEnabled = levelOn
        case "色彩取消":
            colorOff.toggle()
            cameraController.setFilterColorOff(colorOff)
        case "白平衡":
            toggleActiveTool(.wb)
        case "感光":
            toggleActiveTool(.iso)
        case "快门速度":
            toggleActiveTool(.shutter)
        case "曝光":
            toggleActiveTool(.ev)
        case "锐度":
            toggleActiveTool(.sharpness)
        case "对比度":
            toggleActiveTool(.contrast)
        case "饱和度":
            toggleActiveTool(.saturation)
        default:
            break
        }
    }

    private func toggleActiveTool(_ tool: ActiveTool) {
        activeTool = activeTool == tool ? .none : tool
    }

    private var activeToolTitle: String {
        switch activeTool {
        case .wb:
            return "WB"
        case .iso:
            return "ISO"
        case .shutter:
            return "Shutter"
        case .ev:
            return "EV"
        case .sharpness:
            return "Sharpness"
        case .contrast:
            return "Contrast"
        case .saturation:
            return "Saturation"
        case .none:
            return ""
        }
    }

    private func formattedRulerValue() -> String {
        switch activeTool {
        case .wb:
            return "\(Int(rulerValue))K"
        case .iso:
            return "\(Int(rulerValue.rounded()))"
        case .shutter:
            if rulerValue >= 1.0 {
                return String(format: "%.1fs", rulerValue)
            }
            let denominator = Int((1.0 / max(0.000001, rulerValue)).rounded())
            return "1/\(denominator)s"
        case .ev:
            return String(format: "%.1f", rulerValue)
        case .sharpness, .contrast, .saturation:
            return String(format: "%.2f", rulerValue)
        case .none:
            return ""
        }
    }

    private func initialRulerValue(for tool: ActiveTool) -> Double {
        switch tool {
        case .wb:
            let value = Double(cameraController.currentWhiteBalanceTemperature() ?? 5000)
            return clampAndStep(value, for: .wb)
        case .iso:
            let range = isoRange()
            let mid = (range.lowerBound + range.upperBound) / 2.0
            let current = Double(cameraController.currentISOValue() ?? Float(mid))
            return clampAndStep(current, for: .iso)
        case .shutter:
            let current = cameraController.currentExposureDurationSeconds() ?? (1.0 / 60.0)
            return clampAndStep(current, for: .shutter)
        case .ev:
            let current = Double(cameraController.currentExposureBias() ?? 0)
            return clampAndStep(current, for: .ev)
        case .sharpness:
            return clampAndStep(sharpness, for: .sharpness)
        case .contrast:
            return clampAndStep(contrast, for: .contrast)
        case .saturation:
            return clampAndStep(saturation, for: .saturation)
        case .none:
            return rulerValue
        }
    }

    private func applyRulerValueIfNeeded(_ newValue: Double) {
        guard activeTool != .none else { return }
        let clamped = clampAndStep(newValue, for: activeTool)
        if clamped != newValue {
            rulerValue = clamped
            return
        }

        let now = CACurrentMediaTime()
        if now - lastCommitTime < (1.0 / 30.0) {
            return
        }
        lastCommitTime = now

        switch activeTool {
        case .wb:
            cameraController.setWhiteBalance(temperature: Int(rulerValue), tint: 0)
        case .iso:
            cameraController.setISO(Float(rulerValue))
        case .shutter:
            cameraController.setShutter(durationSeconds: rulerValue)
        case .ev:
            cameraController.setExposureBias(Float(rulerValue))
        case .sharpness:
            sharpness = rulerValue
            cameraController.setFilterSharpness(rulerValue)
        case .contrast:
            contrast = rulerValue
            cameraController.setFilterContrast(rulerValue)
        case .saturation:
            saturation = rulerValue
            cameraController.setFilterSaturation(rulerValue)
        case .none:
            break
        }
    }

    private func setAutoForActiveTool() {
        switch activeTool {
        case .wb:
            cameraController.setWhiteBalance(temperature: nil, tint: nil)
        case .iso:
            cameraController.setISO(nil)
        case .shutter:
            cameraController.setShutter(durationSeconds: nil)
        case .ev:
            cameraController.setExposureBias(nil)
        case .sharpness:
            sharpness = 0
            cameraController.setFilterSharpness(0)
        case .contrast:
            contrast = 1
            cameraController.setFilterContrast(1)
        case .saturation:
            saturation = 1
            cameraController.setFilterSaturation(1)
        case .none:
            break
        }
    }

    private func requestAutoValue(completion: @escaping (Double) -> Void) {
        switch activeTool {
        case .wb:
            cameraController.getCurrentWBTemperature { value in
                completion(Double(value))
            }
        case .iso:
            cameraController.getCurrentISO { value in
                completion(Double(value))
            }
        case .shutter:
            cameraController.getCurrentShutterSeconds { value in
                completion(value)
            }
        case .ev:
            cameraController.getCurrentEV { value in
                completion(Double(value))
            }
        case .sharpness:
            completion(0)
        case .contrast:
            completion(1)
        case .saturation:
            completion(1)
        case .none:
            completion(rulerValue)
        }
    }

    private func isoRange() -> ClosedRange<Double> {
        if let range = cameraController.exposedISORange {
            return Double(range.lowerBound)...Double(range.upperBound)
        }
        return 50.0...800.0
    }

    private func wbRange() -> ClosedRange<Double> {
        2500.0...9000.0
    }

    private func shutterRange() -> ClosedRange<Double> {
        (1.0 / 8000.0)...(1.0 / 15.0)
    }

    private func evRange() -> ClosedRange<Double> {
        if let range = cameraController.exposedEVRange {
            return Double(range.lowerBound)...Double(range.upperBound)
        }
        return -4.0...4.0
    }

    private func sharpnessRange() -> ClosedRange<Double> {
        0.0...1.0
    }

    private func contrastRange() -> ClosedRange<Double> {
        0.5...2.0
    }

    private func saturationRange() -> ClosedRange<Double> {
        0.0...2.0
    }

    private func stepValue(for tool: ActiveTool) -> Double {
        switch tool {
        case .wb:
            return 50.0
        case .iso:
            let range = isoRange()
            let span = range.upperBound - range.lowerBound
            return span > 400 ? 10.0 : 5.0
        case .ev:
            return 0.1
        case .sharpness, .contrast, .saturation:
            return 0.05
        case .shutter, .none:
            return 1.0
        }
    }

    private func clampAndStep(_ value: Double, for tool: ActiveTool) -> Double {
        switch tool {
        case .wb:
            let range = wbRange()
            return clampAndStepLinear(value, range: range, step: stepValue(for: tool))
        case .iso:
            let range = isoRange()
            return clampAndStepLinear(value, range: range, step: stepValue(for: tool))
        case .ev:
            let range = evRange()
            return clampAndStepLinear(value, range: range, step: stepValue(for: tool))
        case .sharpness:
            return clampAndStepLinear(value, range: sharpnessRange(), step: stepValue(for: tool))
        case .contrast:
            return clampAndStepLinear(value, range: contrastRange(), step: stepValue(for: tool))
        case .saturation:
            return clampAndStepLinear(value, range: saturationRange(), step: stepValue(for: tool))
        case .shutter:
            return clampAndStepShutter(value)
        case .none:
            return value
        }
    }

    private func clampAndStepLinear(_ value: Double, range: ClosedRange<Double>, step: Double) -> Double {
        let clamped = max(range.lowerBound, min(range.upperBound, value))
        let stepped = ((clamped - range.lowerBound) / step).rounded() * step + range.lowerBound
        return max(range.lowerBound, min(range.upperBound, stepped))
    }

    private func clampAndStepShutter(_ value: Double) -> Double {
        let range = shutterRange()
        let minSec = range.lowerBound
        let maxSec = range.upperBound
        let minLog = log2(minSec)
        let maxLog = log2(maxSec)
        let stepStops = 1.0 / 3.0

        let logValue = log2(max(minSec, min(maxSec, value)))
        let clampedLog = max(minLog, min(maxLog, logValue))
        let roundedLog = (clampedLog / stepStops).rounded() * stepStops
        let snapped = pow(2.0, roundedLog)
        return max(minSec, min(maxSec, snapped))
    }

    private func normalizedValue(for tool: ActiveTool, value: Double) -> Double {
        switch tool {
        case .shutter:
            let range = shutterRange()
            let minLog = log2(range.lowerBound)
            let maxLog = log2(range.upperBound)
            let logValue = log2(max(range.lowerBound, min(range.upperBound, value)))
            return (logValue - minLog) / (maxLog - minLog)
        case .wb:
            return linearNormalize(value, range: wbRange())
        case .iso:
            return linearNormalize(value, range: isoRange())
        case .ev:
            return linearNormalize(value, range: evRange())
        case .sharpness:
            return linearNormalize(value, range: sharpnessRange())
        case .contrast:
            return linearNormalize(value, range: contrastRange())
        case .saturation:
            return linearNormalize(value, range: saturationRange())
        case .none:
            return 0
        }
    }

    private func valueFromNormalized(for tool: ActiveTool, normalized: Double) -> Double {
        let t = max(0.0, min(1.0, normalized))
        switch tool {
        case .shutter:
            let range = shutterRange()
            let minLog = log2(range.lowerBound)
            let maxLog = log2(range.upperBound)
            let logValue = minLog + (maxLog - minLog) * t
            return pow(2.0, logValue)
        case .wb:
            return linearDenormalize(t, range: wbRange())
        case .iso:
            return linearDenormalize(t, range: isoRange())
        case .ev:
            return linearDenormalize(t, range: evRange())
        case .sharpness:
            return linearDenormalize(t, range: sharpnessRange())
        case .contrast:
            return linearDenormalize(t, range: contrastRange())
        case .saturation:
            return linearDenormalize(t, range: saturationRange())
        case .none:
            return 0
        }
    }

    private func linearNormalize(_ value: Double, range: ClosedRange<Double>) -> Double {
        let clamped = max(range.lowerBound, min(range.upperBound, value))
        let span = max(0.000001, range.upperBound - range.lowerBound)
        return (clamped - range.lowerBound) / span
    }

    private func linearDenormalize(_ t: Double, range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound
        return range.lowerBound + span * t
    }
}

struct RulerControl: View {
    let title: String
    let valueText: String
    @Binding var value: Double
    let normalizedValue: (Double) -> Double
    let valueFromNormalized: (Double) -> Double
    let clampAndStep: (Double) -> Double
    let autoSelectedFlag: Bool
    let onAutoSelectedChange: (Bool) -> Void
    let onManualChange: () -> Void
    let onRequestAutoValue: (@escaping (Double) -> Void) -> Void
    let onAuto: () -> Void
    let onDone: () -> Void

    @State private var thumbX: CGFloat = 0
    @State private var availableWidth: CGFloat = 0
    @State private var isDraggingThumb: Bool = false
    @State private var isAutoSelected: Bool = false
    @State private var lastHapticTime: CFTimeInterval = 0
    @State private var autoTimer: Timer? = nil

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: onDone) {
                    Text("Done")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Spacer()

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.8))

                Text(valueText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.yellow.opacity(0.9))
            }

            GeometryReader { geometry in
                let width = max(geometry.size.width, 1)
                let maxX = max(1, width / 2)

                ZStack {
                    rulerTicks(width: width)
                        .frame(height: 40)

                    Rectangle()
                        .fill(Color.yellow.opacity(0.9))
                        .frame(width: 2, height: 40)
                        .offset(x: thumbX)
                }
                .frame(height: 40)
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            if !isDraggingThumb {
                                isDraggingThumb = true
                                stopAutoPolling()
                                triggerHaptic(force: true)
                            }
                            isAutoSelected = false
                            onAutoSelectedChange(false)
                            onManualChange()

                            let sensitivity: CGFloat = 1.5
                            let centeredX = (gesture.location.x - width / 2) * sensitivity
                            let clampedX = max(-maxX, min(maxX, centeredX))
                            thumbX = clampedX

                            let t = Double((clampedX + maxX) / (2 * maxX))
                            let newValue = clampAndStep(valueFromNormalized(t))
                            if newValue != value {
                                value = newValue
                                triggerHaptic(force: false)
                            }
                        }
                        .onEnded { _ in
                            isDraggingThumb = false
                            if isAutoSelected {
                                startAutoPolling()
                            }
                        }
                )
                .onAppear {
                    availableWidth = width
                    isAutoSelected = autoSelectedFlag
                    syncThumbFromValue()
                }
                .onChange(of: width) { newValue in
                    availableWidth = newValue
                    syncThumbFromValue()
                }
            }
            .frame(height: 40)

            Button(action: {
                isAutoSelected = true
                onAutoSelectedChange(true)
                onAuto()
                requestAutoSync(force: true)
                startAutoPolling()
            }) {
                Text("Auto")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isAutoSelected ? Color.black.opacity(0.9) : Color.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isAutoSelected ? Color.yellow.opacity(0.9) : Color.white.opacity(0.12))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .onChange(of: value) { _ in
            syncThumbFromValue()
        }
        .onChange(of: autoSelectedFlag) { newValue in
            if !isDraggingThumb {
                isAutoSelected = newValue
                if newValue {
                    requestAutoSync(force: true)
                    startAutoPolling()
                } else {
                    stopAutoPolling()
                }
            }
        }
        .onDisappear {
            stopAutoPolling()
        }
    }

    private func syncThumbFromValue() {
        guard !isDraggingThumb else { return }
        let maxX = max(1, availableWidth / 2)
        let t = max(0.0, min(1.0, normalizedValue(value)))
        thumbX = CGFloat(t * 2.0 - 1.0) * maxX
    }

    private func requestAutoSync(force: Bool) {
        if !force, !isAutoSelected {
            return
        }
        onRequestAutoValue { autoValue in
            let clamped = clampAndStep(autoValue)
            if clamped != value {
                value = clamped
            }
            syncThumbFromValue()
        }
    }

    private func startAutoPolling() {
        guard isAutoSelected else { return }
        if autoTimer != nil {
            return
        }
        autoTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            requestAutoSync(force: false)
        }
    }

    private func stopAutoPolling() {
        autoTimer?.invalidate()
        autoTimer = nil
    }

    private func triggerHaptic(force: Bool) {
        let now = CACurrentMediaTime()
        if !force && now - lastHapticTime < 0.05 {
            return
        }
        lastHapticTime = now
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    private func rulerTicks(width: CGFloat) -> some View {
        let tickCount = 61
        let spacing: CGFloat = 10
        let totalWidth = CGFloat(tickCount - 1) * spacing

        return HStack(spacing: spacing) {
            ForEach(0..<tickCount, id: \.self) { index in
                let isMajor = index % 5 == 0
                Rectangle()
                    .fill(Color.white.opacity(isMajor ? 0.7 : 0.35))
                    .frame(width: 1, height: isMajor ? 18 : 10)
            }
        }
        .frame(width: totalWidth, height: 40)
        .frame(width: width, height: 40, alignment: .center)
    }
}

// 工具数据模型
struct ToolItem: Identifiable {
    let id: String
    let title: String
    let systemName: String
    let isEnabled: Bool

    init(title: String, systemName: String, isEnabled: Bool = true) {
        self.id = title
        self.title = title
        self.systemName = systemName
        self.isEnabled = isEnabled
    }
}

// 单个工具按钮
struct ToolButtonView: View {
    let title: String
    let systemName: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isSelected ? Color.yellow.opacity(0.9) : Color.white.opacity(0.8))
                    .frame(width: 28, height: 24)

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isSelected ? Color.yellow.opacity(0.9) : Color.white.opacity(0.7))
            }
            .frame(minWidth: 48)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1.0 : 0.35)
        .allowsHitTesting(isEnabled)
    }
}

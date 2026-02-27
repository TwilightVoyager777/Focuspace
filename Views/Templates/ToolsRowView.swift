import SwiftUI
import QuartzCore

// 底部工具条（C1）
struct BottomC1ToolsRowView: View {
    @ObservedObject var cameraController: CameraSessionController
    @Binding var isAdjusting: Bool
    var useLandscapeSidebarLayout: Bool = false

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

    private var isActiveToolAdjusting: Bool {
        activeTool != .none
    }
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
            ToolItem(title: "Front", systemName: "camera.rotate"),
            ToolItem(title: "White Balance", systemName: "circle.lefthalf.filled"),
            ToolItem(title: "ISO", systemName: "sun.max"),
            ToolItem(title: "Shutter", systemName: "timer"),
            ToolItem(title: "Exposure", systemName: "circle.dashed")
        ]

        if !isVideoMode {
            list.append(contentsOf: [
                ToolItem(title: "Saturation", systemName: "drop.fill"),
                ToolItem(title: "Contrast", systemName: "circle.righthalf.filled"),
                ToolItem(title: "Sharpness", systemName: "camera.filters"),
                ToolItem(title: "Color Off", systemName: "circle.slash")
            ])
        }

        list.append(contentsOf: [
            ToolItem(title: "Level", systemName: "ruler", isEnabled: levelEnabled)
        ])

        return list
    }

    // 默认高亮项
    private let selectedTitle: String = "ISO"

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
                    },
                    useVerticalLayout: useLandscapeSidebarLayout
                )
                .offset(y: useLandscapeSidebarLayout ? 0 : -8)
                .onDisappear {
                    isAdjusting = false
                }
            }
        }
        .onChange(of: activeTool) { _, newValue in
            rulerValue = initialRulerValue(for: newValue)
            isAdjusting = newValue != .none
        }
        .onAppear {
            isAdjusting = isActiveToolAdjusting
        }
        .onChange(of: rulerValue) { _, newValue in
            applyRulerValueIfNeeded(newValue)
        }
        .onChange(of: cameraController.captureMode) { _, newValue in
            if newValue == .video {
                if activeTool == .sharpness || activeTool == .contrast || activeTool == .saturation {
                    activeTool = .none
                }
            }
            isAdjusting = isActiveToolAdjusting
        }
    }

    private var toolsRow: some View {
        Group {
            if useLandscapeSidebarLayout {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(items) { item in
                            ToolButtonView(
                                title: item.title,
                                systemName: item.systemName,
                                isSelected: isItemSelected(item),
                                isEnabled: item.isEnabled,
                                useLandscapeSidebarLayout: true,
                                action: {
                                    handleTap(for: item.title)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                }
            } else {
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
        }
    }

    private func isItemSelected(_ item: ToolItem) -> Bool {
        switch item.title {
        case "Level":
            return levelOn
        case "Color Off":
            return colorOff
        case "White Balance":
            return activeTool == .wb
        case "ISO":
            return activeTool == .iso
        case "Shutter":
            return activeTool == .shutter
        case "Exposure":
            return activeTool == .ev
        case "Sharpness":
            return activeTool == .sharpness
        case "Contrast":
            return activeTool == .contrast
        case "Saturation":
            return activeTool == .saturation
        default:
            return item.title == selectedTitle
        }
    }

    private func handleTap(for title: String) {
        switch title {
        case "Front":
            cameraController.switchCamera()
        case "Level":
            levelOn.toggle()
            cameraController.isLevelOverlayEnabled = levelOn
        case "Color Off":
            colorOff.toggle()
            cameraController.setFilterColorOff(colorOff)
        case "White Balance":
            toggleActiveTool(.wb)
        case "ISO":
            toggleActiveTool(.iso)
        case "Shutter":
            toggleActiveTool(.shutter)
        case "Exposure":
            toggleActiveTool(.ev)
        case "Sharpness":
            toggleActiveTool(.sharpness)
        case "Contrast":
            toggleActiveTool(.contrast)
        case "Saturation":
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
            completion(Double(cameraController.currentWhiteBalanceTemperature() ?? 5000))
        case .iso:
            completion(Double(cameraController.currentISOValue() ?? 100))
        case .shutter:
            completion(cameraController.currentExposureDurationSeconds() ?? (1.0 / 60.0))
        case .ev:
            completion(Double(cameraController.currentExposureBias() ?? 0))
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

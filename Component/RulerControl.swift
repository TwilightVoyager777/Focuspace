import SwiftUI
import QuartzCore
import UIKit

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
    var useVerticalLayout: Bool = false

    @State private var thumbX: CGFloat = 0
    @State private var availableWidth: CGFloat = 0
    @State private var isDraggingThumb: Bool = false
    @State private var isAutoSelected: Bool = false
    @State private var lastHapticTime: CFTimeInterval = 0
    @State private var autoTimer: Timer? = nil

    var body: some View {
        Group {
            if useVerticalLayout {
                HStack(spacing: 10) {
                    VStack(spacing: 8) {
                        buttonDone
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.8))

                        Text(valueText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.yellow.opacity(0.9))

                        buttonAuto
                    }
                    .frame(width: 64, alignment: .top)

                    GeometryReader { geometry in
                        let height = max(geometry.size.height, 1)
                        let maxOffset = max(1, height / 2)

                        ZStack {
                            rulerTicksVertical(height: height)
                                .frame(width: 40)

                            Rectangle()
                                .fill(Color.yellow.opacity(0.9))
                                .frame(width: 36, height: 2)
                                .offset(y: thumbX)
                        }
                        .frame(width: 40, height: height)
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
                                    let centered = (gesture.location.y - height / 2) * sensitivity
                                    let clamped = max(-maxOffset, min(maxOffset, centered))
                                    thumbX = clamped

                                    let t = Double((clamped + maxOffset) / (2 * maxOffset))
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
                            availableWidth = height
                            isAutoSelected = autoSelectedFlag
                            syncThumbFromValue()
                        }
                        .onChange(of: height) { _, newValue in
                            availableWidth = newValue
                            syncThumbFromValue()
                        }
                    }
                    .frame(width: 40)
                }
            } else {
                VStack(spacing: 10) {
                    HStack {
                        buttonDone

                        Spacer()

                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.8))

                        Text(valueText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.yellow.opacity(0.9))

                        Spacer()

                        buttonAuto
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
                        .onChange(of: width) { _, newValue in
                            availableWidth = newValue
                            syncThumbFromValue()
                        }
                    }
                    .frame(height: 40)
                }
            }
        }
        .padding(.horizontal, 8)
        .onChange(of: value) { _, _ in
            syncThumbFromValue()
        }
        .onChange(of: autoSelectedFlag) { _, newValue in
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
            Task { @MainActor in
                requestAutoSync(force: false)
            }
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

    private var buttonDone: some View {
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
    }

    private var buttonAuto: some View {
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

    private func rulerTicksVertical(height: CGFloat) -> some View {
        let tickCount = 61
        let spacing: CGFloat = 10
        let totalHeight = CGFloat(tickCount - 1) * spacing

        return VStack(spacing: spacing) {
            ForEach(0..<tickCount, id: \.self) { index in
                let isMajor = index % 5 == 0
                Rectangle()
                    .fill(Color.white.opacity(isMajor ? 0.7 : 0.35))
                    .frame(width: isMajor ? 18 : 10, height: 1)
            }
        }
        .frame(width: 40, height: totalHeight)
        .frame(width: 40, height: height, alignment: .center)
    }
}

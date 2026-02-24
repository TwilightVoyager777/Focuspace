import SwiftUI

struct BreathingDotView: View {
    enum ZoomCue {
        case none
        case zoomIn
        case zoomOut
    }

    // 核心点大小。
    var coreDiameter: CGFloat = 6
    // 内发光大小与柔和程度。
    var glowDiameter: CGFloat = 20
    // 中间清晰环大小与线宽。
    var midRingDiameter: CGFloat = 20
    var midRingLineWidth: CGFloat = 1.5
    // 外部呼吸环大小、线宽与羽化。
    var outerRingDiameter: CGFloat = 25
    var outerRingLineWidth: CGFloat = 3
    var outerRingBlur: CGFloat = 14
    // 内发光羽化。
    var glowBlur: CGFloat = 6
    // 呼吸动画参数。
    var pulseScaleTo: CGFloat = 0.86
    var pulseOpacityFrom: CGFloat = 0.10
    var pulseOpacityTo: CGFloat = 0.22
    var pulseDuration: Double = 1.4

    // 引导位移：移动整个点位（含所有层），用于提示镜头向某个方向移动。
    var guidanceOffset: CGSize = .zero
    // 引导强度，范围 [0, 1]。
    var strength: CGFloat = 0
    // 是否处于对齐保持状态。
    var isHolding: Bool = false
    // 缩放提示：zoomIn/zoomOut 时触发一次性脉冲缩放，不影响外环呼吸。
    var zoomCue: ZoomCue = .none
    // 左右倾斜提示，范围 [-1, 1]。通过压扁环形并轻微旋转表达倾斜方向。
    var tiltCue: CGFloat = 0

    @State private var isPulsing = false
    @State private var zoomScale: CGFloat = 1.0

    // 位移限制：限制在安全半径内，避免点位移出视觉区域。
    private var clampedGuidanceOffset: CGSize {
        GuidanceUIConstants.clampedGuidanceOffset(guidanceOffset)
    }

    // 夹取倾斜值，避免超出预期范围。
    private var clampedTilt: CGFloat {
        min(max(tiltCue, -1), 1)
    }

    private var clampedStrength: CGFloat {
        min(max(strength, 0), 1)
    }

    private var directionSign: CGFloat {
        guidanceOffset.width == 0 ? 0 : (guidanceOffset.width > 0 ? 1 : -1)
    }

    private var outerRingOpacity: CGFloat {
        let base = isPulsing ? pulseOpacityTo : pulseOpacityFrom
        return base * (isHolding ? 0.6 : 1.0)
    }

    // 倾斜压扁程度：|tilt| 越大，Y 方向越扁。
    private var tiltScaleY: CGFloat {
        max(0.75, 1.0 - abs(clampedTilt) * 0.25)
    }

    // 倾斜旋转：轻微左右“倾倒”。
    private var tiltRotation: Angle {
        .degrees(8 * clampedTilt)
    }

    var body: some View {
        ZStack {
            // 核心点。
            Circle()
                .fill(Color.white)
                .frame(width: coreDiameter, height: coreDiameter)

            // 内发光。
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            Color.white.opacity(0.35),
                            Color.white.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: glowDiameter / 2
                    )
                )
                .frame(width: glowDiameter, height: glowDiameter)
                .blur(radius: glowBlur)
                .scaleEffect(x: 1.0, y: tiltScaleY)
                .rotationEffect(tiltRotation)

            // 中间清晰环。
            Circle()
                .stroke(Color.white.opacity(0.85), lineWidth: midRingLineWidth)
                .frame(width: midRingDiameter, height: midRingDiameter)
                .scaleEffect(x: 1.0, y: tiltScaleY)
                .rotationEffect(tiltRotation)

            // 外部呼吸环。
            Circle()
                .stroke(Color.white.opacity(pulseOpacityFrom), lineWidth: outerRingLineWidth)
                .frame(width: outerRingDiameter, height: outerRingDiameter)
                .blur(radius: outerRingBlur)
                .scaleEffect(isPulsing ? pulseScaleTo : 1.0)
                .scaleEffect(x: 1.0, y: tiltScaleY)
                .rotationEffect(tiltRotation)
                .opacity(outerRingOpacity)
                .animation(
                    .easeInOut(duration: pulseDuration).repeatForever(autoreverses: true),
                    value: isPulsing
                )

            // 引导弧形轨迹。
            Circle()
                .trim(from: 0.06, to: 0.06 + 0.10 + 0.10 * clampedStrength)
                .stroke(
                    Color.white.opacity(0.6 + 0.4 * clampedStrength),
                    style: StrokeStyle(lineWidth: 1.0 + 1.2 * clampedStrength, lineCap: .round)
                )
                .frame(
                    width: outerRingDiameter + 12 + 10 * clampedStrength,
                    height: outerRingDiameter + 12 + 10 * clampedStrength
                )
                .opacity(isHolding ? 0 : (0.2 + 0.8 * clampedStrength))
                .rotationEffect(
                    .degrees((directionSign >= 0 ? 18 : -18) + (isPulsing ? 8 : -8))
                )
                .animation(
                    .easeInOut(duration: pulseDuration).repeatForever(autoreverses: true),
                    value: isPulsing
                )
        }
        // 一次性缩放提示（独立于外环呼吸）
        .scaleEffect(zoomScale)
        .offset(clampedGuidanceOffset)
        .animation(
            .interpolatingSpring(stiffness: 140, damping: 18),
            value: clampedGuidanceOffset
        )
        .allowsHitTesting(false)
        .onAppear {
            isPulsing = true
        }
        // 根据 zoomCue 触发一次性缩放脉冲。
        .onChange(of: zoomCue) { newValue in
            switch newValue {
            case .none:
                break
            case .zoomIn:
                withAnimation(.easeInOut(duration: 0.12)) {
                    zoomScale = 1.12
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        zoomScale = 1.0
                    }
                }
            case .zoomOut:
                withAnimation(.easeInOut(duration: 0.12)) {
                    zoomScale = 0.90
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        zoomScale = 1.0
                    }
                }
            }
        }
    }
}

struct BreathingDotView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            BreathingDotView()
        }
    }
}

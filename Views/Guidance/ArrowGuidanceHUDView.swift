import SwiftUI

struct ArrowGuidanceHUDView: View {
    enum CrosshairStyle {
        case standard
        case scope
    }

    var guidanceOffset: CGSize
    var strength: CGFloat = 0
    var isHolding: Bool = false
    var crosshairStyle: CrosshairStyle = .standard

    private var clampedStrength: CGFloat {
        min(max(strength, 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let displayedOffset = isHolding ? .zero : guidanceOffset
            let maxRadiusPx = GuidanceUIConstants.scaledMaxRadius(for: geo.size)
            let clampedOffset = GuidanceUIConstants.snappedGuidanceOffset(
                displayedOffset,
                maxRadiusPx: maxRadiusPx
            )
            let dxPx = clampedOffset.width
            let dyPx = clampedOffset.height
            let distance = sqrt(dxPx * dxPx + dyPx * dyPx)
            let arrowOpacity = isHolding ? 0 : (0.25 + 0.75 * clampedStrength)
            let headLength: CGFloat = 5 + 6 * clampedStrength
            let cx = geo.size.width * 0.5
            let cy = geo.size.height * 0.5
            let center = CGPoint(x: cx, y: cy)
            let target = CGPoint(x: cx + dxPx, y: cy + dyPx)
            let markerClearance: CGFloat = {
                switch crosshairStyle {
                case .scope:
                    return 14.0
                case .standard:
                    let ringSize = 16 + clampedStrength * 6
                    // Keep arrow tip outside the target ring (radius + stroke + visual gap).
                    return (ringSize * 0.5) + 3.0
                }
            }()
            let effectiveDistance = distance - markerClearance

            ZStack {
                if crosshairStyle == .standard {
                    crosshairView
                        .opacity(0.95)
                }

                // Arrow from center to camera-move target
                Path { path in
                    guard effectiveDistance >= (headLength + 1) else { return }
                    let ux = (target.x - center.x) / distance
                    let uy = (target.y - center.y) / distance
                    let tip = CGPoint(
                        x: target.x - ux * markerClearance,
                        y: target.y - uy * markerClearance
                    )
                    let shaftEnd = CGPoint(
                        x: tip.x - ux * headLength,
                        y: tip.y - uy * headLength
                    )
                    path.move(to: center)
                    path.addLine(to: shaftEnd)

                    let angle = atan2(tip.y - center.y, tip.x - center.x)
                    let headAngle: CGFloat = 0.6
                    let left = CGPoint(
                        x: tip.x - cos(angle - headAngle) * headLength,
                        y: tip.y - sin(angle - headAngle) * headLength
                    )
                    let right = CGPoint(
                        x: tip.x - cos(angle + headAngle) * headLength,
                        y: tip.y - sin(angle + headAngle) * headLength
                    )
                    path.move(to: tip)
                    path.addLine(to: left)
                    path.move(to: tip)
                    path.addLine(to: right)
                }
                .stroke(
                    Color.white,
                    style: StrokeStyle(
                        lineWidth: crosshairStyle == .scope ? 2.2 : 2.0,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: crosshairStyle == .scope ? [6, 4] : [5, 4]
                    )
                )
                .opacity(effectiveDistance < (headLength + 1) ? 0 : arrowOpacity)

                if crosshairStyle == .scope {
                    scopeSubjectMarker(offset: clampedOffset)
                } else {
                    standardTargetRing(
                        offset: clampedOffset,
                        strength: clampedStrength,
                        isHolding: isHolding
                    )
                }

                if crosshairStyle == .scope {
                    // Keep scope crosshair on top so the marker glow won't mask its shape.
                    crosshairView
                        .opacity(0.98)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var crosshairView: some View {
        switch crosshairStyle {
        case .standard:
            StandardCenterDotView(isHolding: isHolding)
        case .scope:
            GuidanceScopeCrosshairView(isHolding: isHolding)
        }
    }

    @ViewBuilder
    private func standardTargetRing(offset: CGSize, strength: CGFloat, isHolding: Bool) -> some View {
        StandardTargetRingView(
            offset: offset,
            strength: strength,
            isHolding: isHolding
        )
    }

    @ViewBuilder
    private func scopeSubjectMarker(offset: CGSize) -> some View {
        ScopeTargetMarkerView(
            offset: offset,
            isHolding: isHolding
        )
    }
}

private struct StandardCenterDotView: View {
    let isHolding: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(isHolding ? 0.90 : 0.98))
                .frame(width: 3.8, height: 3.8)
            Circle()
                .stroke(Color.white.opacity(isHolding ? 0.20 : 0.35), lineWidth: 1.0)
                .frame(width: 7.6, height: 7.6)
        }
        .shadow(color: .black.opacity(0.26), radius: 1.0, x: 0, y: 0)
        .allowsHitTesting(false)
    }
}

private struct StandardTargetRingView: View {
    let offset: CGSize
    let strength: CGFloat
    let isHolding: Bool

    @State private var isPulsing: Bool = false

    var body: some View {
        let ringSize = 16 + strength * 6
        let ringScale: CGFloat = isHolding ? 0.94 : (isPulsing ? 1.06 : 0.98)
        let ringOpacity: CGFloat = isHolding ? 0.60 : 0.90

        Circle()
            .stroke(Color.white.opacity(ringOpacity), lineWidth: 2.0)
            .frame(width: ringSize, height: ringSize)
            .scaleEffect(ringScale)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(isHolding ? 0.18 : 0.28), lineWidth: 0.9)
                    .frame(width: ringSize + 3, height: ringSize + 3)
                    .scaleEffect(ringScale)
            )
            .offset(offset)
            .animation(
                .interpolatingSpring(stiffness: 140, damping: 18),
                value: offset
            )
            .allowsHitTesting(false)
            .onAppear {
                guard isPulsing == false else { return }
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

private struct ScopeTargetMarkerView: View {
    let offset: CGSize
    let isHolding: Bool

    var body: some View {
        let markerSize: CGFloat = 20
        let corner: CGFloat = 5.8
        let style = StrokeStyle(
            lineWidth: 2.1,
            lineCap: .round,
            lineJoin: .round,
            dash: [4.8, 3.2]
        )
        let gradient = LinearGradient(
            colors: [
                .white, Color(red: 0.36, green: 0.68, blue: 1.0), .white
            ],
            startPoint: .leading,
            endPoint: .trailing
        )

        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .stroke(gradient, style: style)
            .frame(width: markerSize, height: markerSize)
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Color.white.opacity(isHolding ? 0.12 : 0.20), lineWidth: 0.8)
            )
            .opacity(isHolding ? 0.50 : 0.95)
            .offset(offset)
            .animation(
                .interpolatingSpring(stiffness: 140, damping: 18),
                value: offset
            )
            .allowsHitTesting(false)
    }
}

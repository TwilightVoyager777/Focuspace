import SwiftUI

// 取景区域
struct ViewfinderView: View {
    // 是否显示网格线（构图辅助）
    private let showsGrid: Bool = true

    // 当前缩放值（双指捏合实时更新）
    @State private var zoomValue: CGFloat = 1.0
    // 基准缩放值（用于累计多次捏合）
    @State private var baseZoom: CGFloat = 1.0
    // 缩放提示胶囊显示控制
    @State private var showZoomBadge: Bool = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // 中间区域用黑色作为留白背景（letterboxing）
                Color.black

                // 4:3 取景区域居中显示
                VStack(spacing: 0) {
                    Spacer()

                    ZStack {
                        // 取景区域占位：中性灰渐变
                        LinearGradient(
                            colors: [Color(.systemGray4), Color(.systemGray2)],
                            startPoint: .top,
                            endPoint: .bottom
                        )

                        // 三等分网格线，可用于构图
                        if showsGrid {
                            GridOverlayView()
                                .padding(1)
                        }
                    }
                    // 用缩放比例模拟取景放大效果
                    .scaleEffect(zoomValue)
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
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
                    // 双指捏合缩放（无 UI 控件）
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                showZoomBadge = true
                                let updated = baseZoom * value
                                zoomValue = clamp(updated, min: 0.5, max: 8.0)
                            }
                            .onEnded { _ in
                                baseZoom = zoomValue
                                withAnimation(.easeOut(duration: 0.25)) {
                                    showZoomBadge = false
                                }
                            }
                    )

                    Spacer()
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
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

// 三等分网格线
struct GridOverlayView: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let thirdWidth = size.width / 3
            let thirdHeight = size.height / 3

            Path { path in
                path.move(to: CGPoint(x: thirdWidth, y: 0))
                path.addLine(to: CGPoint(x: thirdWidth, y: size.height))

                path.move(to: CGPoint(x: thirdWidth * 2, y: 0))
                path.addLine(to: CGPoint(x: thirdWidth * 2, y: size.height))

                path.move(to: CGPoint(x: 0, y: thirdHeight))
                path.addLine(to: CGPoint(x: size.width, y: thirdHeight))

                path.move(to: CGPoint(x: 0, y: thirdHeight * 2))
                path.addLine(to: CGPoint(x: size.width, y: thirdHeight * 2))
            }
            .stroke(Color.white.opacity(0.2), lineWidth: 1)
        }
    }
}

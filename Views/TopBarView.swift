import SwiftUI

// 顶部状态栏区域
struct TopBarView: View {
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            // 顶部区域背景
            Color.black

            // 顶部内容在 TopBar 内部垂直居中
            VStack(alignment: .center, spacing: 0) {
                Spacer()

                ZStack {
                    HStack {
                        CircularIconButtonView(systemName: "bolt.slash")

                        Spacer()

                        CircularIconButtonView(systemName: "ellipsis")
                    }

                    // 中间分段控件固定居中，不受左右宽度影响
                    SegmentedModeView()
                }
                .padding(.horizontal, 16)

                Spacer()
            }

            // 顶部小绿点提示（占位）
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
                .offset(y: 6)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }
}

// 顶部分段控件（视频 / 动态）
struct SegmentedModeView: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("视频")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))

            // 默认选中“动态”
            Text("动态")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.6))
                .cornerRadius(10)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.white.opacity(0.18))
        .cornerRadius(14)
    }
}

// 顶部圆形图标按钮
struct CircularIconButtonView: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 32, height: 32)
            .background(Color.white.opacity(0.15))
            .clipShape(Circle())
    }
}

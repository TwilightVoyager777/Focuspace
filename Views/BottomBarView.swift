import SwiftUI

// 底部控制区域
struct BottomBarView: View {
    let height: CGFloat

    var body: some View {
        ZStack {
            // 底部区域背景
            Color.black

            VStack(spacing: 18) {
                // 工具条（可横向滚动）
                BottomC1ToolsRowView()
                // 下方控制行：缩略图 + 快门 + 切换镜头
                BottomControlsView()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }
}

// 底部快门区域（左缩略图 + 中快门 + 右切换）
struct BottomControlsView: View {
    var body: some View {
        ZStack {
            // 左右按钮占位，使用 Spacer 推到两侧
            HStack {
                RecentThumbnailView()

                Spacer()

                CameraSwitchButtonView()
            }

            // 中间快门按钮叠加，保证始终居中
            ShutterButtonView()
        }
    }
}

// 快门按钮
struct ShutterButtonView: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.6), lineWidth: 6)
                .frame(width: 86, height: 86)

            Circle()
                .fill(Color.white)
                .frame(width: 72, height: 72)
        }
    }
}

// 左侧最近缩略图
struct RecentThumbnailView: View {
    var body: some View {
        Circle()
            .fill(Color.white.opacity(0.2))
            .frame(width: 49, height: 49)
            .overlay(
                Circle().stroke(Color.white.opacity(0.5), lineWidth: 1)
            )
    }
}

// 右侧镜头切换按钮
struct CameraSwitchButtonView: View {
    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath.camera")
            .font(.system(size: 22, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 49, height: 49)
    }
}

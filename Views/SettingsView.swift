import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var simpleMode: Bool = false
    @State private var stabilization: Bool = true
    @State private var grid: Bool = false
    @State private var level: Bool = true
    @State private var saveHint: Bool = true

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    header

                    SectionCard(title: "拍摄") {
                        ToggleRow(icon: "camera", title: "简易模式", isOn: $simpleMode)
                        ToggleRow(icon: "camera.on.rectangle", title: "稳定器", isOn: $stabilization)
                        ToggleRow(icon: "square.grid.3x3", title: "预览网格", isOn: $grid)
                        ToggleRow(icon: "ruler", title: "水平指示器", isOn: $level)
                        ToggleRow(icon: "square.and.arrow.down", title: "存储空间提示", isOn: $saveHint)
                        InfoRow(icon: "mappin.and.ellipse", title: "录制保存地理位置", trailing: "前往授权")
                    }

                    SectionTitle(text: "Creative")
                    NavigationLink {
                        CompositionLabView(selectTemplate: { _ in })
                    } label: {
                        CardRow(title: "Composition Lab", icon: "square.grid.2x2")
                    }
                    .buttonStyle(.plain)
                    
                    SectionTitle(text: "性能")
                    CardRow(title: "性能设置", icon: "speedometer")
                    CardRow(title: "转录模式", icon: "bubble.left.and.bubble.right", trailing: "仅录制图片")

                    SectionTitle(text: "通用")

                    CardRow(title: "清除缓存", icon: "trash", trailing: "51.38MB")
                    CardRow(title: "关于我们", icon: "info.circle")
                    CardRow(title: "常见问题", icon: "questionmark.circle")
                    CardRow(title: "反馈与建议", icon: "envelope")
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
        }
        .navigationBarHidden(true)
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("设置")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            Color.clear
                .frame(width: 32, height: 32)
        }
        .padding(.top, 6)
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        HStack {
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

struct ToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 22)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Color.green.opacity(0.9))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(rowBackground)
    }

    private var rowBackground: some View {
        Color.white.opacity(0.001)
            .overlay(
                Divider()
                    .background(Color.white.opacity(0.08)),
                alignment: .bottom
            )
    }
}

struct InfoRow: View {
    let icon: String
    let title: String
    let trailing: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 22)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            Text(trailing)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.green.opacity(0.9))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct CardRow: View {
    let title: String
    let icon: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 22)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            if let trailing {
                Text(trailing)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

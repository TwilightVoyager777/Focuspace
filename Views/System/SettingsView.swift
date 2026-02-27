import SwiftUI

struct SettingsView: View {
    let onSelectTemplate: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var debugSettings: DebugSettings

    @State private var simpleMode: Bool = false
    @State private var stabilization: Bool = true
    @State private var level: Bool = true
    @State private var saveHint: Bool = true

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    header

                    SectionCard(title: "Capture") {
                        ToggleRow(icon: "camera", title: "Simple Mode", isOn: $simpleMode)
                        ToggleRow(icon: "camera.on.rectangle", title: "Stabilization", isOn: $stabilization)
                        ToggleRow(icon: "square.grid.3x3", title: "Preview Grid", isOn: $debugSettings.showGridOverlay)
                        ToggleRow(icon: "ruler", title: "Level Indicator", isOn: $level)
                        ToggleRow(icon: "square.and.arrow.down", title: "Storage Warning", isOn: $saveHint)
                        InfoRow(icon: "mappin.and.ellipse", title: "Save Location for Recordings", trailing: "Grant Access")
                    }

                    SectionTitle(text: "Creative")
                    NavigationLink {
                        CompositionLabView(
                            selectTemplate: onSelectTemplate,
                            closeLab: { dismiss() }
                        )
                    } label: {
                        CardRow(title: "Composition Lab", icon: "square.grid.2x2")
                    }
                    .buttonStyle(.plain)
                    
                    SectionCard(title: "Debug") {
                        ToggleRow(icon: "waveform.path.ecg", title: "Guidance Debug HUD", isOn: $debugSettings.showGuidanceDebugHUD)
                        ToggleRow(icon: "brain.head.profile", title: "AI Debug HUD", isOn: $debugSettings.showAICoachDebugHUD)
                        GuidanceModeRow(title: "Guidance UI", selection: $debugSettings.guidanceUIMode)
                    }

                    SectionTitle(text: "Performance")
                    CardRow(title: "Performance Settings", icon: "speedometer")
                    CardRow(title: "Recording Mode", icon: "bubble.left.and.bubble.right", trailing: "Images Only")

                    SectionTitle(text: "General")

                    CardRow(title: "Clear Cache", icon: "trash", trailing: "51.38MB")
                    CardRow(title: "About", icon: "info.circle")
                    CardRow(title: "FAQ", icon: "questionmark.circle")
                    CardRow(title: "Feedback", icon: "envelope")
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

            Text("Settings")
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

struct GuidanceModeRow: View {
    let title: String
    @Binding var selection: DebugSettings.GuidanceUIMode

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 22)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            Picker("Guidance UI", selection: $selection) {
                Text("Moving").tag(DebugSettings.GuidanceUIMode.moving)
                Text("Arrow").tag(DebugSettings.GuidanceUIMode.arrow)
                Text("Scope").tag(DebugSettings.GuidanceUIMode.arrowScope)
            }
            .pickerStyle(.segmented)
            .frame(width: 230)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Color.white.opacity(0.001)
                .overlay(
                    Divider()
                        .background(Color.white.opacity(0.08)),
                    alignment: .bottom
                )
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

import SwiftUI

struct SettingsView: View {
    let onSelectTemplate: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var debugSettings: DebugSettings

    var body: some View {
        GeometryReader { proxy in
            let usePadLandscapeLayout = UIDevice.current.userInterfaceIdiom == .pad && proxy.size.width > proxy.size.height
            let topInset: CGFloat = usePadLandscapeLayout ? max(proxy.safeAreaInsets.top, 10) + 24 : 6

            ZStack {
                Color.black
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        header(topInset: topInset)

                        SectionCard(title: "Capture") {
                            ToggleRow(icon: "square.grid.3x3", title: "Preview Grid", isOn: $debugSettings.showGridOverlay)
                            GuidanceModeRow(title: "Guidance UI", selection: $debugSettings.guidanceUIMode)
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
                        SectionCard(title: "Creative") {
                            ToggleRow(icon: "square.on.square.dashed", title: "Template Overlay", isOn: $debugSettings.showTemplateOverlay)
                        }

                        SectionCard(title: "Foundation Models") {
                            ToggleRow(icon: "viewfinder.circle", title: "Smart Template Button", isOn: $debugSettings.showSmartTemplateButton)
                            InfoTextRow(
                                text: "Smart Template does not rely entirely on Foundation Models. This app always keeps an algorithm-based recommendation fallback, so Smart Template can still work in Swift Playgrounds without Foundation Models. Foundation Models only enhance scene understanding and template recommendation when available. In Swift Playgrounds, Foundation Models may still run with limited capability, so for the full intelligent composition experience, open this project in Xcode and run it on a supported device."
                            )
                        }

                        SectionCard(title: "Debug") {
                            ToggleRow(icon: "waveform.path.ecg", title: "Guidance Debug HUD", isOn: $debugSettings.showGuidanceDebugHUD)
                            ToggleRow(icon: "brain.head.profile", title: "AI Debug HUD", isOn: $debugSettings.showAICoachDebugHUD)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 0)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationBarHidden(true)
    }

    private func header(topInset: CGFloat) -> some View {
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
        .padding(.top, topInset)
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
                Text("Scope").tag(DebugSettings.GuidanceUIMode.arrowScope)
                Text("Moving").tag(DebugSettings.GuidanceUIMode.moving)
                Text("Arrow").tag(DebugSettings.GuidanceUIMode.arrow)
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

struct InfoTextRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white.opacity(0.82))
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .lineSpacing(2)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
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

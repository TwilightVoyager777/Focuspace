import SwiftUI
import UIKit

struct CompositionLabView: View {
    let selectTemplate: (String) -> Void
    let closeLab: () -> Void

    private let templates: [CompositionTemplate] = sortTemplates(TemplateCatalog.load())

    var body: some View {
        GeometryReader { proxy in
            let usePadLandscapeLayout = UIDevice.current.userInterfaceIdiom == .pad && proxy.size.width > proxy.size.height
            let spacing: CGFloat = usePadLandscapeLayout ? 18 : 16
            let horizontalPadding: CGFloat = usePadLandscapeLayout ? 28 : 20
            let columns: [GridItem] = {
                if usePadLandscapeLayout {
                    let targetCardWidth: CGFloat = 210
                    let rawCount = Int((proxy.size.width - horizontalPadding * 2 + spacing) / (targetCardWidth + spacing))
                    let count = max(4, min(6, rawCount))
                    return Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
                }
                return [GridItem(.adaptive(minimum: 150), spacing: spacing)]
            }()

            ScrollView {
                LazyVGrid(columns: columns, spacing: spacing) {
                    ForEach(templates) { template in
                        NavigationLink {
                            TemplateDetailView(template: template, selectTemplate: selectTemplate, closeLab: closeLab)
                        } label: {
                            TemplateCardView(
                                template: template,
                                usePadLandscapeLayout: usePadLandscapeLayout
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, usePadLandscapeLayout ? 14 : 12)
                .padding(.bottom, usePadLandscapeLayout ? 30 : 24)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Composition Lab")
            .navigationBarTitleDisplayMode(usePadLandscapeLayout ? .inline : .large)
            .onAppear {
                #if DEBUG
                validateAssets(for: templates)
                #endif
            }
        }
    }

    private func validateAssets(for templates: [CompositionTemplate]) {
        for template in templates {
            for asset in template.examples {
                if UIImage(named: asset) == nil {
                    print("Missing template asset: \(asset)")
                }
            }
        }
    }
}

struct TemplateCardView: View {
    let template: CompositionTemplate
    var usePadLandscapeLayout: Bool = false

    private var resolvedExamples: [String] {
        TemplateCatalog.resolvedExamples(templateID: template.id, explicit: template.examples)
    }

    var body: some View {
        let tileCorner: CGFloat = usePadLandscapeLayout ? 14 : 12
        let cardCorner: CGFloat = usePadLandscapeLayout ? 16 : 14

        VStack(alignment: .leading, spacing: 10) {
            ExampleTileView(
                assetName: resolvedExamples.first,
                fallbackLabel: template.name,
                cornerRadius: tileCorner,
                aspect: 4.0 / 3.0
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(.system(size: usePadLandscapeLayout ? 17 : 14, weight: .bold))
                    .foregroundColor(.white)

                Text(template.subtitle)
                    .font(.system(size: usePadLandscapeLayout ? 14 : 12, weight: .regular))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(usePadLandscapeLayout ? 2 : 1)
            }
        }
        .padding(usePadLandscapeLayout ? 14 : 12)
        .background(Color(white: 0.07))
        .clipShape(RoundedRectangle(cornerRadius: cardCorner, style: .continuous))
        .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
    }
}

struct TemplateDetailView: View {
    let template: CompositionTemplate
    let selectTemplate: (String) -> Void
    let closeLab: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedAsset: SelectedAsset? = nil

    var body: some View {
        GeometryReader { proxy in
            let usePadLandscapeLayout = UIDevice.current.userInterfaceIdiom == .pad && proxy.size.width > proxy.size.height

            ScrollView {
                if usePadLandscapeLayout {
                    let horizontalPadding: CGFloat = 28
                    let leftColumnWidth = min(420, max(320, proxy.size.width * 0.36))
                    let rightContentWidth = max(260, proxy.size.width - horizontalPadding * 2 - leftColumnWidth - 24)

                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 22) {
                            heroSection(usePadLandscapeLayout: true)
                            howToUseSection(usePadLandscapeLayout: true)
                        }
                        .frame(width: leftColumnWidth, alignment: .topLeading)

                        examplesSection(
                            usePadLandscapeLayout: true,
                            maxWidth: rightContentWidth
                        )
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 14)
                    .padding(.bottom, 32)
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        heroSection(usePadLandscapeLayout: false)
                        examplesSection(usePadLandscapeLayout: false, maxWidth: proxy.size.width - 44)
                        howToUseSection(usePadLandscapeLayout: false)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Composition Lab")
            .navigationBarTitleDisplayMode(usePadLandscapeLayout ? .inline : .large)
        }
        .fullScreenCover(item: $selectedAsset) { asset in
            ImageLightboxView(assetName: asset.id) {
                selectedAsset = nil
            }
        }
    }

    private var resolvedExamples: [String] {
        TemplateCatalog.resolvedExamples(
            templateID: template.id,
            explicit: template.examples
        )
    }

    private func heroSection(usePadLandscapeLayout: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(template.name)
                .font(.system(size: usePadLandscapeLayout ? 32 : 26, weight: .bold))
                .foregroundColor(.white)

            Text(template.philosophy)
                .font(.system(size: usePadLandscapeLayout ? 17 : 14, weight: .regular))
                .foregroundColor(.white.opacity(0.7))

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
                    .background(Color(white: 0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                CompositionDiagramView(templateID: template.id)
                    .stroke(Color.white.opacity(0.8), lineWidth: 1.2)
                    .padding(24)
            }
            .frame(height: usePadLandscapeLayout ? 210 : 180)

            Button {
                selectTemplate(template.id)
                closeLab()
            } label: {
                Text("Start Shooting")
                    .font(.system(size: usePadLandscapeLayout ? 17 : 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func examplesSection(usePadLandscapeLayout: Bool, maxWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Examples")
                .font(.system(size: usePadLandscapeLayout ? 16 : 14, weight: .bold))
                .foregroundColor(.white)

            if usePadLandscapeLayout {
                let spacing: CGFloat = 12
                let cellWidth = max(130, min(260, (maxWidth - spacing) / 2))
                let columns = [
                    GridItem(.fixed(cellWidth), spacing: spacing),
                    GridItem(.fixed(cellWidth), spacing: spacing)
                ]

                LazyVGrid(columns: columns, spacing: spacing) {
                    ForEach(resolvedExamples, id: \.self) { assetName in
                        ExampleTileView(
                            assetName: assetName,
                            fallbackLabel: assetName,
                            cornerRadius: 10,
                            aspect: 4.0 / 3.0
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            let feedback = UIImpactFeedbackGenerator(style: .light)
                            feedback.impactOccurred()
                            selectedAsset = SelectedAsset(id: assetName)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(resolvedExamples, id: \.self) { assetName in
                            ExampleTileView(
                                assetName: assetName,
                                fallbackLabel: assetName,
                                cornerRadius: 8,
                                aspect: 4.0 / 3.0
                            )
                            .frame(height: 150)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                let feedback = UIImpactFeedbackGenerator(style: .light)
                                feedback.impactOccurred()
                                selectedAsset = SelectedAsset(id: assetName)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func howToUseSection(usePadLandscapeLayout: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How To Use")
                .font(.system(size: usePadLandscapeLayout ? 16 : 14, weight: .bold))
                .foregroundColor(.white)

            ForEach(bullets(for: template.id), id: \.self) { bullet in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundColor(.white.opacity(0.85))
                    Text(bullet)
                        .font(.system(size: usePadLandscapeLayout ? 15 : 13, weight: .regular))
                        .foregroundColor(.white.opacity(0.75))
                }
            }
        }
    }

    private func bullets(for id: String) -> [String] {
        TemplateRegistry.usageBullets(for: id) ?? [
            "Give the subject room to breathe.",
            "Use emptiness to emphasize form.",
            "Simplify the background."
        ]
    }

}

struct ImageLightboxView: View {
    let assetName: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = UIImage(named: assetName), !assetName.isEmpty {
                ZoomableImageView(image: image)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Color(white: 0.2), Color(white: 0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    Text(assetName.isEmpty ? "No image" : assetName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.horizontal, 16)
                }
                .frame(width: 260, height: 195)
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .padding(.top, 12)
                    .padding(.trailing, 12)
                }
                Spacer()
            }
        }
    }
}

private struct ZoomableImageView: View {
    let image: UIImage

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let maxX = (geo.size.width * (scale - 1.0)) / 2.0
            let maxY = (geo.size.height * (scale - 1.0)) / 2.0

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(scale, anchor: .center)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = max(1.0, min(3.0, lastScale * value))
                            if scale <= 1.0 {
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                        .onEnded { _ in
                            scale = max(1.0, min(3.0, scale))
                            if scale == 1.0 {
                                offset = .zero
                                lastOffset = .zero
                            }
                            lastScale = scale
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard scale > 1.0 else { return }
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            guard scale > 1.0 else {
                                offset = .zero
                                lastOffset = .zero
                                return
                            }
                            let clamped = CGSize(
                                width: min(max(offset.width, -maxX), maxX),
                                height: min(max(offset.height, -maxY), maxY)
                            )
                            offset = clamped
                            lastOffset = clamped
                        }
                )
                .onTapGesture(count: 2) {
                    if scale > 1.0 {
                        scale = 1.0
                        lastScale = 1.0
                        offset = .zero
                        lastOffset = .zero
                    } else {
                        scale = 2.5
                        lastScale = 2.5
                        offset = .zero
                        lastOffset = .zero
                    }
                }
        }
    }
}

struct CompositionDiagramView: Shape {
    let templateID: String

    func path(in rect: CGRect) -> Path {
        let inset = min(rect.width, rect.height) * 0.08
        let r = rect.insetBy(dx: inset, dy: inset)
        var path = Path()
        path.addPath(borderPath(in: r))

        switch templateID {
        case "rule_of_thirds":
            path.addPath(thirdsPath(in: r))
        case "golden_spiral":
            path.addPath(goldenSpiralPath(in: r))
        case "center":
            path.addPath(centerPath(in: r))
        case "symmetry":
            path.addPath(symmetryPath(in: r))
        case "leading_lines":
            path.addPath(leadingLinesPath(in: r))
        case "framing":
            path.addPath(framingPath(in: r))
        case "portrait_headroom":
            path.addPath(portraitHeadroomPath(in: r))
        case "diagonals":
            path.addPath(diagonalsPath(in: r))
        case "triangle":
            path.addPath(trianglePath(in: r))
        case "layers_fmb":
            path.addPath(layersFMBPath(in: r))
        default:
            path.addPath(negativeSpacePath(in: r))
        }

        return path
    }

    private func borderPath(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) * 0.06
        var path = Path()
        path.addRoundedRect(in: rect, cornerSize: CGSize(width: radius, height: radius))
        return path
    }

    private func thirdsPath(in rect: CGRect) -> Path {
        var path = Path()
        let thirdW = rect.width / 3
        let thirdH = rect.height / 3
        let x1 = rect.minX + thirdW
        let x2 = rect.minX + thirdW * 2
        let y1 = rect.minY + thirdH
        let y2 = rect.minY + thirdH * 2

        path.move(to: CGPoint(x: x1, y: rect.minY))
        path.addLine(to: CGPoint(x: x1, y: rect.maxY))
        path.move(to: CGPoint(x: x2, y: rect.minY))
        path.addLine(to: CGPoint(x: x2, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: y1))
        path.addLine(to: CGPoint(x: rect.maxX, y: y1))
        path.move(to: CGPoint(x: rect.minX, y: y2))
        path.addLine(to: CGPoint(x: rect.maxX, y: y2))

        let dotRadius = min(rect.width, rect.height) * 0.02
        let dots = [
            CGPoint(x: x1, y: y1),
            CGPoint(x: x2, y: y1),
            CGPoint(x: x1, y: y2),
            CGPoint(x: x2, y: y2)
        ]
        for dot in dots {
            let dotRect = CGRect(
                x: dot.x - dotRadius,
                y: dot.y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            )
            path.addEllipse(in: dotRect)
        }

        let centerRadius = dotRadius * 0.45
        let centerRect = CGRect(
            x: rect.midX - centerRadius,
            y: rect.midY - centerRadius,
            width: centerRadius * 2,
            height: centerRadius * 2
        )
        path.addEllipse(in: centerRect)
        return path
    }

    private func goldenSpiralPath(in rect: CGRect) -> Path {
        var path = Path()
        let maxIterations = 7
        var remaining = rect
        var direction = remaining.width >= remaining.height ? 0 : 1

        for _ in 0..<maxIterations {
            let size = min(remaining.width, remaining.height)
            let square: CGRect

            switch direction {
            case 0:
                square = CGRect(x: remaining.minX, y: remaining.minY, width: size, height: size)
                remaining = CGRect(
                    x: remaining.minX + size,
                    y: remaining.minY,
                    width: remaining.width - size,
                    height: remaining.height
                )
            case 1:
                square = CGRect(x: remaining.minX, y: remaining.minY, width: size, height: size)
                remaining = CGRect(
                    x: remaining.minX,
                    y: remaining.minY + size,
                    width: remaining.width,
                    height: remaining.height - size
                )
            case 2:
                square = CGRect(x: remaining.maxX - size, y: remaining.minY, width: size, height: size)
                remaining = CGRect(
                    x: remaining.minX,
                    y: remaining.minY,
                    width: remaining.width - size,
                    height: remaining.height
                )
            default:
                square = CGRect(x: remaining.minX, y: remaining.maxY - size, width: size, height: size)
                remaining = CGRect(
                    x: remaining.minX,
                    y: remaining.minY,
                    width: remaining.width,
                    height: remaining.height - size
                )
            }

            path.addRect(square)

            let center: CGPoint
            let startAngle: Angle
            let endAngle: Angle

            switch direction {
            case 0:
                center = CGPoint(x: square.maxX, y: square.minY)
                startAngle = .degrees(90)
                endAngle = .degrees(180)
            case 1:
                center = CGPoint(x: square.maxX, y: square.maxY)
                startAngle = .degrees(180)
                endAngle = .degrees(270)
            case 2:
                center = CGPoint(x: square.minX, y: square.maxY)
                startAngle = .degrees(270)
                endAngle = .degrees(360)
            default:
                center = CGPoint(x: square.minX, y: square.minY)
                startAngle = .degrees(0)
                endAngle = .degrees(90)
            }

            path.addArc(
                center: center,
                radius: size,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: false
            )

            if remaining.width <= 0 || remaining.height <= 0 {
                break
            }

            direction = (direction + 1) % 4
        }

        return path
    }

    private func centerPath(in rect: CGRect) -> Path {
        var path = Path()
        let minSide = min(rect.width, rect.height)
        let tick = minSide * 0.12
        let circleRadius = minSide * 0.18
        let innerRadius = circleRadius * 0.55

        path.move(to: CGPoint(x: rect.midX - tick, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX + tick, y: rect.midY))
        path.move(to: CGPoint(x: rect.midX, y: rect.midY - tick))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY + tick))

        let outerRect = CGRect(
            x: rect.midX - circleRadius,
            y: rect.midY - circleRadius,
            width: circleRadius * 2,
            height: circleRadius * 2
        )
        let innerRect = CGRect(
            x: rect.midX - innerRadius,
            y: rect.midY - innerRadius,
            width: innerRadius * 2,
            height: innerRadius * 2
        )
        path.addEllipse(in: outerRect)
        path.addEllipse(in: innerRect)

        let box = rect.insetBy(dx: rect.width * 0.28, dy: rect.height * 0.28)
        path.addRoundedRect(in: box, cornerSize: CGSize(width: minSide * 0.04, height: minSide * 0.04))
        return path
    }

    private func symmetryPath(in rect: CGRect) -> Path {
        var path = Path()
        let offset = rect.width * 0.06
        let tick = rect.height * 0.08

        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))

        path.move(to: CGPoint(x: rect.midX - tick, y: rect.minY + tick))
        path.addLine(to: CGPoint(x: rect.midX + tick, y: rect.minY + tick))
        path.move(to: CGPoint(x: rect.midX - tick, y: rect.maxY - tick))
        path.addLine(to: CGPoint(x: rect.midX + tick, y: rect.maxY - tick))

        path.move(to: CGPoint(x: rect.midX - offset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX - offset, y: rect.maxY))
        path.move(to: CGPoint(x: rect.midX + offset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + offset, y: rect.maxY))

        return path
    }

    private func leadingLinesPath(in rect: CGRect) -> Path {
        var path = Path()
        let focal = CGPoint(x: rect.minX + rect.width * 0.66, y: rect.minY + rect.height * 0.33)

        let sources = [
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.15),
            CGPoint(x: rect.maxX, y: rect.midY + rect.height * 0.15)
        ]

        for source in sources {
            path.move(to: source)
            path.addLine(to: focal)
        }

        let dotRadius = min(rect.width, rect.height) * 0.025
        let dotRect = CGRect(
            x: focal.x - dotRadius,
            y: focal.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        )
        path.addEllipse(in: dotRect)
        return path
    }

    private func framingPath(in rect: CGRect) -> Path {
        var path = Path()
        let marginX = rect.width * 0.14
        let marginY = rect.height * 0.14
        let inner = rect.insetBy(dx: marginX, dy: marginY)
        let segment = min(inner.width, inner.height) * 0.22

        path.move(to: CGPoint(x: inner.minX, y: inner.minY + segment))
        path.addLine(to: CGPoint(x: inner.minX, y: inner.minY))
        path.addLine(to: CGPoint(x: inner.minX + segment, y: inner.minY))

        path.move(to: CGPoint(x: inner.maxX - segment, y: inner.minY))
        path.addLine(to: CGPoint(x: inner.maxX, y: inner.minY))
        path.addLine(to: CGPoint(x: inner.maxX, y: inner.minY + segment))

        path.move(to: CGPoint(x: inner.minX, y: inner.maxY - segment))
        path.addLine(to: CGPoint(x: inner.minX, y: inner.maxY))
        path.addLine(to: CGPoint(x: inner.minX + segment, y: inner.maxY))

        path.move(to: CGPoint(x: inner.maxX - segment, y: inner.maxY))
        path.addLine(to: CGPoint(x: inner.maxX, y: inner.maxY))
        path.addLine(to: CGPoint(x: inner.maxX, y: inner.maxY - segment))

        return path
    }

    private func portraitHeadroomPath(in rect: CGRect) -> Path {
        var path = Path()
        let headroomY = rect.minY + rect.height * 0.12
        let eyeLineY = rect.minY + rect.height * 0.38
        let shouldersY = rect.minY + rect.height * 0.72
        let shoulderSpan = rect.width * 0.7

        path.move(to: CGPoint(x: rect.minX, y: headroomY))
        path.addLine(to: CGPoint(x: rect.maxX, y: headroomY))
        path.move(to: CGPoint(x: rect.minX, y: eyeLineY))
        path.addLine(to: CGPoint(x: rect.maxX, y: eyeLineY))

        let ovalW = rect.width * 0.28
        let ovalH = rect.height * 0.36
        let ovalRect = CGRect(
            x: rect.midX - ovalW / 2,
            y: rect.minY + rect.height * 0.20,
            width: ovalW,
            height: ovalH
        )
        path.addEllipse(in: ovalRect)

        path.move(to: CGPoint(x: rect.midX - shoulderSpan / 2, y: shouldersY))
        path.addLine(to: CGPoint(x: rect.midX + shoulderSpan / 2, y: shouldersY))
        return path
    }

    private func diagonalsPath(in rect: CGRect) -> Path {
        var path = Path()
        let m = min(rect.width, rect.height) * 0.06

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + m, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + m))
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - m))
        path.addLine(to: CGPoint(x: rect.maxX - m, y: rect.minY))
        return path
    }

    private func trianglePath(in rect: CGRect) -> Path {
        var path = Path()
        let apex = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.18)
        let baseLeft = CGPoint(x: rect.minX, y: rect.maxY)
        let baseRight = CGPoint(x: rect.maxX, y: rect.maxY)

        path.move(to: baseLeft)
        path.addLine(to: baseRight)
        path.addLine(to: apex)
        path.addLine(to: baseLeft)

        let dotRadius = min(rect.width, rect.height) * 0.02
        let dotRect = CGRect(
            x: apex.x - dotRadius,
            y: apex.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        )
        path.addEllipse(in: dotRect)
        return path
    }

    private func layersFMBPath(in rect: CGRect) -> Path {
        var path = Path()
        let y1 = rect.minY + rect.height * 0.33
        let y2 = rect.minY + rect.height * 0.66

        path.move(to: CGPoint(x: rect.minX, y: y1))
        path.addLine(to: CGPoint(x: rect.maxX, y: y1))
        path.move(to: CGPoint(x: rect.minX, y: y2))
        path.addLine(to: CGPoint(x: rect.maxX, y: y2))

        let midBox = CGRect(
            x: rect.midX - rect.width * 0.11,
            y: rect.minY + rect.height * 0.45,
            width: rect.width * 0.22,
            height: rect.height * 0.18
        )
        path.addRect(midBox)

        let bracketSize = min(rect.width, rect.height) * 0.12
        let bracketOrigin = CGPoint(x: rect.minX + rect.width * 0.08, y: rect.maxY - rect.height * 0.08)
        path.move(to: CGPoint(x: bracketOrigin.x, y: bracketOrigin.y - bracketSize))
        path.addLine(to: bracketOrigin)
        path.addLine(to: CGPoint(x: bracketOrigin.x + bracketSize, y: bracketOrigin.y))

        let horizonY = rect.minY + rect.height * 0.18
        path.move(to: CGPoint(x: rect.minX, y: horizonY))
        path.addLine(to: CGPoint(x: rect.maxX, y: horizonY))
        return path
    }

    private func negativeSpacePath(in rect: CGRect) -> Path {
        var path = Path()
        let boundaryX = rect.minX + rect.width * 0.55
        let subjectBox = CGRect(
            x: rect.minX + rect.width * 0.62,
            y: rect.minY + rect.height * 0.18,
            width: rect.width * 0.22,
            height: rect.height * 0.22
        )

        path.move(to: CGPoint(x: boundaryX, y: rect.minY))
        path.addLine(to: CGPoint(x: boundaryX, y: rect.maxY))
        path.addRect(subjectBox)

        let markerRadius = min(rect.width, rect.height) * 0.02
        let markerRect = CGRect(
            x: subjectBox.midX - markerRadius,
            y: subjectBox.midY - markerRadius,
            width: markerRadius * 2,
            height: markerRadius * 2
        )
        path.addEllipse(in: markerRect)
        return path
    }
}

struct ExampleTileView: View {
    let assetName: String?
    let fallbackLabel: String
    let cornerRadius: CGFloat
    let aspect: CGFloat

    var body: some View {
        ZStack {
            if let assetName, let image = UIImage(named: assetName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ExamplePlaceholderView(label: fallbackLabel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .aspectRatio(aspect, contentMode: .fill)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct ExamplePlaceholderView: View {
    let label: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(white: 0.2), Color(white: 0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
        }
    }
}

private struct SelectedAsset: Identifiable {
    let id: String
}

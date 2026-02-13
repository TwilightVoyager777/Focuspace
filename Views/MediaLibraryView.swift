import AVFoundation
import AVKit
import SwiftUI

// 媒体库页面
struct MediaLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LocalMediaLibrary

    @State private var showBanner: Bool = true
    @State private var selectedTab: MediaLibraryTab = .materials
    @State private var isSelecting: Bool = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var previewItem: MediaItem? = nil
    @State private var toastMessage: String? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                topBar

                if showBanner {
                    warningBanner
                }

                if isSelecting && selectedTab == .materials {
                    selectAllPill
                }

                contentArea

                if !isSelecting {
                    bottomTabs
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)

            if isSelecting {
                selectionActionBar
            }

            if let toastMessage {
                toastView(message: toastMessage)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $previewItem) { item in
            MediaPreviewView(item: item, onExport: { ids in
                Task {
                    await exportSelected(ids: ids)
                }
            }, onDelete: { ids in
                handleDelete(ids: ids)
            })
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }

            Spacer()

            Text("媒体库")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            HStack(spacing: 12) {
                Button(action: {}) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }

                Button(action: toggleSelectionMode) {
                    Text(isSelecting ? "取消" : "选择")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
        }
    }

    private var warningBanner: some View {
        HStack {
            Text("注意！卸载 App 会清空素材且无法恢复！")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)

            Spacer()

            Button(action: { showBanner = false }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var selectAllPill: some View {
        Button(action: toggleSelectAll) {
            HStack(spacing: 6) {
                Image(systemName: isAllSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .semibold))
                Text("全选")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule(style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var contentArea: some View {
        Group {
            switch selectedTab {
            case .materials:
                if library.materials.isEmpty {
                    emptyState(text: "素材库为空或当前筛选条件无素材")
                } else {
                    mediaGrid(items: library.materials)
                }
            case .recycle:
                if library.trashed.isEmpty {
                    emptyState(text: "回收站为空")
                } else {
                    mediaGrid(items: library.trashed)
                }
            }
        }
    }

    private func emptyState(text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white.opacity(0.7))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func mediaGrid(items: [MediaItem]) -> some View {
        ScrollView {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(items) { item in
                    MediaLibraryThumbnailCell(
                        item: item,
                        isSelecting: isSelecting,
                        isSelected: selectedIDs.contains(item.id)
                    )
                    .onTapGesture {
                        handleItemTap(item)
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private var selectionActionBar: some View {
        let isDisabled = selectedIDs.isEmpty
        let isTrash = selectedTab == .recycle

        return VStack {
            Spacer()
            HStack {
                VStack(spacing: 6) {
                    Button(action: {
                        if isTrash {
                            restoreSelected(ids: selectedIDs)
                        } else {
                            handleDelete(ids: selectedIDs)
                        }
                    }) {
                        Image(systemName: isTrash ? "arrow.uturn.left" : "trash")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .disabled(isDisabled)
                    .opacity(isDisabled ? 0.4 : 1.0)

                    Text(isTrash ? "恢复" : "删除")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .opacity(isDisabled ? 0.4 : 1.0)
                }

                Spacer()

                Text("已选中 \(selectedIDs.count) 项")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                VStack(spacing: 6) {
                    Button(action: {
                        if isTrash {
                            deletePermanently(ids: selectedIDs)
                        } else {
                            Task {
                                await exportSelected(ids: selectedIDs)
                            }
                        }
                    }) {
                        Image(systemName: isTrash ? "trash.slash" : "square.and.arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .disabled(isDisabled)
                    .opacity(isDisabled ? 0.4 : 1.0)

                    Text(isTrash ? "彻底删除" : "导出")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .opacity(isDisabled ? 0.4 : 1.0)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Color.black)
            .padding(.bottom, 16)
        }
    }

    private var bottomTabs: some View {
        HStack(spacing: 18) {
            tabItem(title: "素材", systemName: "photo.on.rectangle", isSelected: selectedTab == .materials) {
                selectedTab = .materials
                clearSelectionIfNeeded()
            }
            tabItem(title: "回收站", systemName: "trash", isSelected: selectedTab == .recycle) {
                selectedTab = .recycle
                clearSelectionIfNeeded()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule(style: .continuous))
    }

    private func tabItem(title: String, systemName: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(isSelected ? .black : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.white : Color.clear)
            .clipShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var isAllSelected: Bool {
        let ids = Set(library.materials.map { $0.id })
        return !ids.isEmpty && selectedIDs == ids
    }

    private func toggleSelectAll() {
        let ids = Set(library.materials.map { $0.id })
        if selectedIDs == ids {
            selectedIDs.removeAll()
        } else {
            selectedIDs = ids
        }
    }

    private func toggleSelectionMode() {
        isSelecting.toggle()
        if !isSelecting {
            selectedIDs.removeAll()
        }
    }

    private func clearSelectionIfNeeded() {
        if isSelecting {
            selectedIDs.removeAll()
        }
    }

    private func handleItemTap(_ item: MediaItem) {
        if isSelecting {
            if selectedIDs.contains(item.id) {
                selectedIDs.remove(item.id)
            } else {
                selectedIDs.insert(item.id)
            }
        } else {
            previewItem = item
        }
    }

    private func handleDelete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        library.moveToTrash(ids: ids)
        selectedIDs.removeAll()
    }

    private func restoreSelected(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        library.restoreFromTrash(ids: ids)
        selectedIDs.removeAll()
    }

    private func deletePermanently(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        library.deletePermanently(ids: ids)
        selectedIDs.removeAll()
    }

    private func exportSelected(ids: Set<UUID>) async {
        guard !ids.isEmpty else { return }
        let success = await library.exportToPhotos(ids: ids)
        showToast(message: success ? "Exported to Photos" : "Export failed")
        selectedIDs.removeAll()
    }

    private func showToast(message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            toastMessage = nil
        }
    }

    private func toastView(message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.8))
                .clipShape(Capsule(style: .continuous))
                .padding(.bottom, 24)
        }
    }
}

private enum MediaLibraryTab {
    case materials
    case recycle
}

private struct MediaLibraryThumbnailCell: View {
    let item: MediaItem
    let isSelecting: Bool
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            switch item.type {
            case .photo(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            case .video(let url):
                if let thumbnail = makeVideoThumbnail(url: url) {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.white.opacity(0.1)
                }

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(radius: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                    .padding(6)
            }
        }
        .frame(height: 110)
        .clipped()
        .cornerRadius(8)
    }

    private func makeVideoThumbnail(url: URL) -> UIImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        do {
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }
}

private struct MediaPreviewView: View {
    @Environment(\.dismiss) private var dismiss

    let item: MediaItem
    let onExport: (Set<UUID>) -> Void
    let onDelete: (Set<UUID>) -> Void

    @State private var player: AVPlayer? = nil
    @State private var videoAspectRatio: CGFloat = 9.0 / 16.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: { dismiss() }) {
                        Text("Back")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    Spacer()

                    Button(action: { onExport([item.id]) }) {
                        Text("Export")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    Button(action: {
                        onDelete([item.id])
                        dismiss()
                    }) {
                        Text("Delete")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                Spacer()

                switch item.type {
                case .photo(let image):
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .video(let url):
                    VideoPlayer(player: player)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(videoAspectRatio, contentMode: .fit)
                        .onAppear {
                            if player == nil {
                                player = AVPlayer(url: url)
                            }
                            updateVideoAspectRatio(for: url)
                            player?.play()
                        }
                        .onDisappear {
                            player?.pause()
                        }
                }

                Spacer()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func updateVideoAspectRatio(for url: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVAsset(url: url)
            guard let track = asset.tracks(withMediaType: .video).first else { return }
            let size = track.naturalSize.applying(track.preferredTransform)
            let width = abs(size.width)
            let height = abs(size.height)
            guard height > 0 else { return }
            let ratio = width / height
            DispatchQueue.main.async {
                videoAspectRatio = ratio
            }
        }
    }
}

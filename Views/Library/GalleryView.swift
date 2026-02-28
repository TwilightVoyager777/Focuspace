@preconcurrency import AVFoundation
import AVKit
import Photos
import SwiftUI
import UIKit

// 本地图库（简单缩略图列表）
struct GalleryView: View {
    @ObservedObject var mediaLibrary: LocalMediaLibrary

    @State private var selectedItem: MediaItem? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                let columns = [GridItem(.adaptive(minimum: 90), spacing: 12)]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(mediaLibrary.items) { item in
                        GalleryThumbnailCell(
                            item: item,
                            thumbnail: mediaLibrary.loadThumbnail(for: item)
                        )
                            .onTapGesture {
                                selectedItem = item
                            }
                    }
                }
                .padding(12)
            }
            .navigationTitle("Gallery")
        }
        .sheet(item: $selectedItem) { item in
            GalleryDetailView(item: item)
        }
    }
}

// 缩略图单元
private struct GalleryThumbnailCell: View {
    let item: MediaItem
    let thumbnail: UIImage?

    var body: some View {
        ZStack {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray.opacity(0.3)
            }

            if case .video = item.type {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(radius: 2)
            }
        }
        .frame(width: 90, height: 90)
        .clipped()
        .cornerRadius(8)
    }
}

// 详情页（可导出到系统相册）
private struct GalleryDetailView: View {
    let item: MediaItem

    @State private var exportMessage: String? = nil
    @State private var player: AVPlayer? = nil
    @State private var videoAspectRatio: CGFloat = 9.0 / 16.0

    var body: some View {
        VStack(spacing: 16) {
            switch item.type {
            case .photo(let url):
                if let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 400)
                } else {
                    Color.gray.opacity(0.2)
                        .frame(maxWidth: .infinity, maxHeight: 400)
                }
            case .video(let url):
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: 400)
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

            Button("Export to Photos") {
                exportToPhotos()
            }
            .buttonStyle(.borderedProminent)

            if let exportMessage {
                Text(exportMessage)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    private func exportToPhotos() {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            saveToPhotos()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized || newStatus == .limited {
                        saveToPhotos()
                    } else {
                        exportMessage = "Photos access denied"
                    }
                }
            }
        default:
            exportMessage = "Photos access denied"
        }
    }

    private func saveToPhotos() {
        switch item.type {
        case .photo(let url):
            guard let image = UIImage(contentsOfFile: url.path) else {
                exportMessage = "Export failed"
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }, completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        exportMessage = "Exported"
                    } else {
                        exportMessage = "Export failed"
                        if let error {
                            print("Export error: \(error)")
                        }
                    }
                }
            })
        case .video(let url):
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }, completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        exportMessage = "Exported"
                    } else {
                        exportMessage = "Export failed"
                        if let error {
                            print("Export error: \(error)")
                        }
                    }
                }
            })
        }
    }

    private func updateVideoAspectRatio(for url: URL) {
        Task(priority: .userInitiated) {
            let ratio = await loadVideoAspectRatio(for: url)
            await MainActor.run {
                videoAspectRatio = ratio
            }
        }
    }

    private nonisolated func loadVideoAspectRatio(for url: URL) async -> CGFloat {
        let asset = AVURLAsset(url: url)
        guard let tracks = try? await asset.loadTracks(withMediaType: .video),
              let track = tracks.first,
              let naturalSize = try? await track.load(.naturalSize),
              let preferredTransform = try? await track.load(.preferredTransform) else {
            return 9.0 / 16.0
        }

        let size = naturalSize.applying(preferredTransform)
        let width = abs(size.width)
        let height = abs(size.height)
        guard height > 0 else { return 9.0 / 16.0 }
        return width / height
    }
}

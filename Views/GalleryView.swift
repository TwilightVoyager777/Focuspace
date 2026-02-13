import AVFoundation
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
                        GalleryThumbnailCell(item: item)
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

    var body: some View {
        ZStack {
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
                    Color.gray.opacity(0.3)
                }

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

// 详情页（可导出到系统相册）
private struct GalleryDetailView: View {
    let item: MediaItem

    @State private var exportMessage: String? = nil
    @State private var player: AVPlayer? = nil

    var body: some View {
        VStack(spacing: 16) {
            switch item.type {
            case .photo(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 400)
            case .video(let url):
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: 400)
                    .onAppear {
                        if player == nil {
                            player = AVPlayer(url: url)
                        }
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
        case .photo(let image):
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
}

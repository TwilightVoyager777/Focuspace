@preconcurrency import AVFoundation
import Foundation
import Photos
import SwiftUI
import UIKit

private struct MediaRecord: Identifiable, Codable, Sendable {
    enum MediaKind: String, Codable {
        case photo
        case video
    }

    let id: UUID
    let createdAt: Date
    let originalPath: String
    let thumbPath: String
    var isTrashed: Bool
    var trashedAt: Date?
    var mediaType: MediaKind
}

private struct MediaLibrarySnapshot: Sendable {
    let records: [MediaRecord]
    let items: [MediaItem]
}

private struct PreparedPhotoSave: @unchecked Sendable {
    let record: MediaRecord
    let item: MediaItem
    let latestThumbnail: UIImage?
}

private struct PreparedVideoSave: @unchecked Sendable {
    let record: MediaRecord
    let item: MediaItem
    let latestThumbnail: UIImage?
}

@MainActor
final class LocalMediaLibrary: ObservableObject {
    static let shared: LocalMediaLibrary = LocalMediaLibrary()

    @Published private(set) var items: [MediaItem] = []
    @Published var latestThumbnail: UIImage? = nil

    private var records: [MediaRecord] = []
    private let fileManager: FileManager = FileManager.default
    private let indexFileName: String = "media_index.json"
    private var thumbnailCache: [UUID: UIImage] = [:]

    private var libraryDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let folder = base?.appendingPathComponent("FocuspaceMedia", isDirectory: true)
        return folder ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    private var indexFileURL: URL {
        libraryDirectory.appendingPathComponent(indexFileName)
    }

    private var videoDirectory: URL {
        libraryDirectory.appendingPathComponent("Videos", isDirectory: true)
    }

    init() {
        ensureLibraryDirectory()
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.loadIndex()
        }
    }

    func savePhoto(_ data: Data) async throws {
        ensureLibraryDirectory()
        let libraryDirectory = self.libraryDirectory
        let prepared = try await Task.detached(priority: .utility) {
            let id = UUID()
            let createdAt = Date()
            let originalURL = libraryDirectory.appendingPathComponent("\(id.uuidString).jpg")
            let thumbURL = libraryDirectory.appendingPathComponent("\(id.uuidString)_thumb.jpg")

            try data.write(to: originalURL, options: .atomic)

            guard let image = UIImage(data: data) else {
                throw NSError(
                    domain: "LocalMediaLibrary",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid image data"]
                )
            }

            let generatedThumbnail = LocalMediaLibrary.makeThumbnail(from: image, maxSize: 200)
            if let generatedThumbnail,
               let thumbData = generatedThumbnail.jpegData(compressionQuality: 0.8) {
                try thumbData.write(to: thumbURL, options: .atomic)
            }

            let record = MediaRecord(
                id: id,
                createdAt: createdAt,
                originalPath: originalURL.path,
                thumbPath: thumbURL.path,
                isTrashed: false,
                trashedAt: nil,
                mediaType: .photo
            )

            let item = MediaItem(
                id: id,
                type: .photo(originalURL),
                date: createdAt
            )

            return PreparedPhotoSave(
                record: record,
                item: item,
                latestThumbnail: generatedThumbnail
            )
        }.value

        records.insert(prepared.record, at: 0)
        items.insert(prepared.item, at: 0)
        if let latestThumbnail = prepared.latestThumbnail {
            thumbnailCache[prepared.item.id] = latestThumbnail
        }
        latestThumbnail = prepared.latestThumbnail ?? latestThumbnail
        if prepared.latestThumbnail == nil {
            updateLatestThumbnailFromItems()
        }
        saveIndex()
    }

    func saveVideoFile(at url: URL, id: UUID) async throws {
        ensureLibraryDirectory()
        ensureVideoDirectory()
        let originalURL = videoDirectory.appendingPathComponent("\(id.uuidString).mov")
        let thumbURL = libraryDirectory.appendingPathComponent("\(id.uuidString)_thumb.jpg")
        let prepared = try await Task.detached(priority: .utility) {
            let createdAt = Date()
            let fileManager = FileManager.default

            if fileManager.fileExists(atPath: originalURL.path),
               originalURL.path != url.path {
                try fileManager.removeItem(at: originalURL)
            }
            if originalURL.path != url.path {
                try fileManager.moveItem(at: url, to: originalURL)
            }

            let generatedThumbnail = LocalMediaLibrary.generateVideoThumbnail(url: originalURL, maxSize: 220)
            if let generatedThumbnail,
               let thumbData = generatedThumbnail.jpegData(compressionQuality: 0.8) {
                try thumbData.write(to: thumbURL, options: .atomic)
            }

            let record = MediaRecord(
                id: id,
                createdAt: createdAt,
                originalPath: originalURL.path,
                thumbPath: thumbURL.path,
                isTrashed: false,
                trashedAt: nil,
                mediaType: .video
            )

            let item = MediaItem(
                id: id,
                type: .video(originalURL),
                date: createdAt
            )

            return PreparedVideoSave(
                record: record,
                item: item,
                latestThumbnail: generatedThumbnail
            )
        }.value

        records.insert(prepared.record, at: 0)
        items.insert(prepared.item, at: 0)
        if let latestThumbnail = prepared.latestThumbnail {
            thumbnailCache[prepared.item.id] = latestThumbnail
        }
        latestThumbnail = prepared.latestThumbnail ?? latestThumbnail
        if prepared.latestThumbnail == nil {
            updateLatestThumbnailFromItems()
        }
        saveIndex()
    }

    func moveToTrash(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }

        records = records.map { record in
            if ids.contains(record.id) {
                var updated = record
                updated.isTrashed = true
                updated.trashedAt = Date()
                return updated
            }
            return record
        }
        updateLatestThumbnailFromItems()
        saveIndex()
    }

    func restoreFromTrash(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }

        records = records.map { record in
            if ids.contains(record.id) {
                var updated = record
                updated.isTrashed = false
                updated.trashedAt = nil
                return updated
            }
            return record
        }
        updateLatestThumbnailFromItems()
        saveIndex()
    }

    func deletePermanently(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }

        let removedRecords = records.filter { ids.contains($0.id) }
        records.removeAll { ids.contains($0.id) }
        items.removeAll { ids.contains($0.id) }
        for id in ids {
            thumbnailCache.removeValue(forKey: id)
        }
        updateLatestThumbnailFromItems()
        saveIndex()
        Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            for record in removedRecords {
                try? fileManager.removeItem(atPath: record.originalPath)
                try? fileManager.removeItem(atPath: record.thumbPath)
            }
        }
    }

    func exportToPhotos(ids: Set<UUID>) async -> Bool {
        guard !ids.isEmpty else { return false }

        let targets = records.filter { ids.contains($0.id) }
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    guard status == .authorized || status == .limited else {
                        continuation.resume(returning: false)
                        return
                    }

                    PHPhotoLibrary.shared().performChanges({
                        for record in targets {
                            switch record.mediaType {
                            case .photo:
                                if let image = UIImage(contentsOfFile: record.originalPath) {
                                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                                }
                            case .video:
                                let url = URL(fileURLWithPath: record.originalPath)
                                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                            }
                        }
                    }, completionHandler: { success, error in
                        DispatchQueue.main.async {
                            if success {
                                print("Export success")
                            } else {
                                print("Export failed:", error?.localizedDescription ?? "")
                            }
                            continuation.resume(returning: success)
                        }
                    })
                }
            }
        }
    }

    private var itemsByID: [UUID: MediaItem] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    var materials: [MediaItem] {
        let map = itemsByID
        return records
            .filter { !$0.isTrashed }
            .sorted { $0.createdAt > $1.createdAt }
            .compactMap { map[$0.id] }
    }

    var trashed: [MediaItem] {
        let map = itemsByID
        return records
            .filter { $0.isTrashed }
            .sorted { ($0.trashedAt ?? $0.createdAt) > ($1.trashedAt ?? $1.createdAt) }
            .compactMap { map[$0.id] }
    }

    private func loadIndex() async {
        let indexFileURL = self.indexFileURL
        let snapshot = await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: indexFileURL.path) else {
                return MediaLibrarySnapshot(records: [], items: [])
            }

            do {
                let data = try Data(contentsOf: indexFileURL)
                let decoded = try JSONDecoder().decode([MediaRecord].self, from: data)
                let records = decoded.sorted { $0.createdAt > $1.createdAt }
                let items = records.compactMap { record -> MediaItem? in
                    let originalURL = URL(fileURLWithPath: record.originalPath)
                    guard FileManager.default.fileExists(atPath: originalURL.path) else { return nil }
                    switch record.mediaType {
                    case .photo:
                        return MediaItem(id: record.id, type: .photo(originalURL), date: record.createdAt)
                    case .video:
                        return MediaItem(id: record.id, type: .video(originalURL), date: record.createdAt)
                    }
                }
                return MediaLibrarySnapshot(records: records, items: items)
            } catch {
                return MediaLibrarySnapshot(records: [], items: [])
            }
        }.value

        let currentRecords = records
        let currentItemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let snapshotItemsByID = Dictionary(uniqueKeysWithValues: snapshot.items.map { ($0.id, $0) })

        var mergedRecordsByID = Dictionary(uniqueKeysWithValues: snapshot.records.map { ($0.id, $0) })
        for record in currentRecords {
            mergedRecordsByID[record.id] = record
        }

        let mergedRecords = mergedRecordsByID.values.sorted { $0.createdAt > $1.createdAt }
        records = mergedRecords
        thumbnailCache = thumbnailCache.filter { mergedRecordsByID[$0.key] != nil }
        items = mergedRecords.compactMap { record in
            currentItemsByID[record.id] ?? snapshotItemsByID[record.id]
        }
        updateLatestThumbnailFromItems()
    }

    private func saveIndex() {
        let records = self.records
        let indexFileURL = self.indexFileURL
        let tempURL = libraryDirectory.appendingPathComponent("media_index.tmp")
        Task.detached(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(records)
                try data.write(to: tempURL, options: .atomic)

                if FileManager.default.fileExists(atPath: indexFileURL.path) {
                    try FileManager.default.removeItem(at: indexFileURL)
                }
                try FileManager.default.moveItem(at: tempURL, to: indexFileURL)
            } catch {
                // ignore
            }
        }
    }

    private func ensureLibraryDirectory() {
        if !fileManager.fileExists(atPath: libraryDirectory.path) {
            try? fileManager.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        }
    }

    private func ensureVideoDirectory() {
        if !fileManager.fileExists(atPath: videoDirectory.path) {
            try? fileManager.createDirectory(at: videoDirectory, withIntermediateDirectories: true)
        }
    }

    func loadThumbnail(for item: MediaItem) -> UIImage? {
        if let cached = thumbnailCache[item.id] {
            return cached
        }
        if let record = records.first(where: { $0.id == item.id }),
           !record.thumbPath.isEmpty,
           let image = UIImage(contentsOfFile: record.thumbPath) {
            thumbnailCache[item.id] = image
            return image
        }
        switch item.type {
        case .photo(let url):
            guard let image = UIImage(contentsOfFile: url.path) else { return nil }
            let thumbnail = LocalMediaLibrary.makeThumbnail(from: image, maxSize: 200) ?? image
            thumbnailCache[item.id] = thumbnail
            return thumbnail
        case .video(let url):
            let thumbnail = LocalMediaLibrary.generateVideoThumbnail(url: url, maxSize: 220)
            if let thumbnail {
                thumbnailCache[item.id] = thumbnail
            }
            return thumbnail
        }
    }

    private func updateLatestThumbnailFromItems() {
        if let first = materials.first, let image = loadThumbnail(for: first) {
            latestThumbnail = image
        } else {
            latestThumbnail = nil
        }
    }

    nonisolated private static func makeThumbnail(from image: UIImage, maxSize: CGFloat) -> UIImage? {
        let size = image.size
        let scale = min(maxSize / size.width, maxSize / size.height)
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    nonisolated private static func generateVideoThumbnail(url: URL, maxSize: CGFloat) -> UIImage? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        do {
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            let image = UIImage(cgImage: cgImage)
            return makeThumbnail(from: image, maxSize: maxSize)
        } catch {
            return nil
        }
    }
}

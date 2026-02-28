import Foundation

struct MediaItem: Identifiable, Sendable {
    enum MediaType: Sendable {
        case photo(URL)
        case video(URL)
    }

    let id: UUID
    let type: MediaType
    let date: Date
}

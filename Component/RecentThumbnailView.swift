import SwiftUI

// 左侧最近缩略图
struct RecentThumbnailView: View {
    let latestThumbnail: UIImage?

    var body: some View {
        NavigationLink {
            MediaLibraryView()
        } label: {
            ZStack {
                if let image = latestThumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.white.opacity(0.2)
                }
            }
            .frame(width: 49, height: 49)
            .clipShape(Circle())
            .overlay(
                Circle().stroke(Color.white.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

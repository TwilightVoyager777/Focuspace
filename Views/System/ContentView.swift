import SwiftUI

struct ContentView: View {
    var body: some View {
        // Route to the main camera screen.
        // 路由到主相机界面，作为应用主入口的第一页。
        CameraScreenView()
            .lockIPadToLandscape()
    }
}

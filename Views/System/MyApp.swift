import SwiftUI

@main
struct MyApp: App {
    @StateObject private var debugSettings = DebugSettings()

    var body: some Scene {
        WindowGroup {
            // App entry point.
            // 应用入口，从这里启动整个界面树。
            ContentView()
                .environmentObject(debugSettings)
        }
    }
}

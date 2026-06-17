import SwiftUI

@main
struct Game1MacApp: App {
    var body: some Scene {
        WindowGroup {
            GameView()
                .frame(minWidth: 420, minHeight: 520)
        }
        .windowResizability(.contentMinSize)
    }
}

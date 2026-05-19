import SwiftUI
import AVKit

struct ContentView: View {
    // 1. Create the player by locating "jane.mp4" inside the app bundle
    @State private var player: AVPlayer? = {
        if let bundleURL = Bundle.main.url(forResource: "Jane", withExtension: "mp4") {
            return AVPlayer(url: bundleURL)
        }
        return nil
    }()

    var body: some View {
        // 2. Safely unwrap the player
        if let player = player {
            VideoPlayer(player: player)
                .edgesIgnoringSafeArea(.all)
                .onAppear {
                    player.play()
                }
        } else {
            // Fallback text if Xcode can't find the file
            Text("Video 'jane.mp4' not found in project bundle.")
                .foregroundColor(.red)
        }
    }
}

#Preview {
    ContentView()
}

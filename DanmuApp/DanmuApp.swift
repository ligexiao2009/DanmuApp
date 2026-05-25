import SwiftUI
import AVKit
import KSPlayer

@main
struct DanmuApp: App {
    init() {
        KSOptions.firstPlayerType = KSMEPlayer.self
        KSOptions.secondPlayerType = nil
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AudioSession setup failed:", error)
        }

        // Pre-warm: resolve DNS + TCP to server before user taps anything
        Task.detached {
            _ = try? await APIService.shared.fetchFolders()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

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

        // Pre-warm FFmpeg/KSPlayer: 首次初始化编解码器很重，放到后台提前触发
        Task.detached {
            let options = KSOptions()
            _ = KSPlayerLayer(url: URL(string: "about:blank")!, options: options)
        }

        // Pre-warm UITextField 键盘系统，避免首次点击 TextField 卡顿
        DispatchQueue.main.async {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
                  let window = scene.windows.first else { return }

            let warmup = UITextField(frame: .zero)
            window.addSubview(warmup)
            warmup.isHidden = true
            _ = warmup.becomeFirstResponder()

            var obs: NSObjectProtocol?
            obs = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardDidShowNotification,
                object: nil, queue: .main
            ) { _ in
                warmup.resignFirstResponder()
                warmup.removeFromSuperview()
                if let o = obs { NotificationCenter.default.removeObserver(o) }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

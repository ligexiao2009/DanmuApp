import SwiftUI
import AVKit

struct AVPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> AVPlayerUIView {
        AVPlayerUIView()
    }

    func updateUIView(_ uiView: AVPlayerUIView, context: Context) {
        if uiView.player !== player { uiView.player = player }
    }
}

final class AVPlayerUIView: UIView {
    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        playerLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

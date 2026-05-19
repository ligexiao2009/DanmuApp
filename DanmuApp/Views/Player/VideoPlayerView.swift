import SwiftUI
import KSPlayer

struct VideoPlayerView: UIViewRepresentable {
    @Binding var playerLayer: KSPlayerLayer?

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let layer = playerLayer, let playerView = layer.player.view else { return }
        // Always re-attach video view to current container
        if playerView.superview !== uiView {
            uiView.subviews.forEach { $0.removeFromSuperview() }
            playerView.translatesAutoresizingMaskIntoConstraints = false
            uiView.addSubview(playerView)
            NSLayoutConstraint.activate([
                playerView.topAnchor.constraint(equalTo: uiView.topAnchor),
                playerView.leadingAnchor.constraint(equalTo: uiView.leadingAnchor),
                playerView.bottomAnchor.constraint(equalTo: uiView.bottomAnchor),
                playerView.trailingAnchor.constraint(equalTo: uiView.trailingAnchor),
            ])
        }
    }

    func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        // Don't remove the video view when SwiftUI disposes container
        // It will be re-attached by the next updateUIView call
    }
}

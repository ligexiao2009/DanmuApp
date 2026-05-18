import SwiftUI
import UIKit

struct DanmakuOverlay: UIViewRepresentable {
    @ObservedObject var engine: DanmakuEngine
    var currentTime: Double
    var isPlaying: Bool

    func makeUIView(context: Context) -> DanmakuUIView {
        DanmakuUIView()
    }

    func updateUIView(_ uiView: DanmakuUIView, context: Context) {
        uiView.engine = engine
        uiView.currentTime = currentTime
        uiView.isPlaying = isPlaying
    }
}

final class DanmakuUIView: UIView {
    var engine: DanmakuEngine?
    var currentTime: Double = 0
    var isPlaying: Bool = false

    private var displayLink: CADisplayLink?
    private var drawables: Set<DanmakuEngine.ActiveDanmaku> = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        engine?.update(size: bounds.size)
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if superview != nil { startDisplayLink() } else { stopDisplayLink() }
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let engine else { return }
        let now = link.timestamp * 1000
        let active = engine.tick(currentTime: currentTime, elapsed: link.timestamp)
        let current = Set(active)

        // Remove finished danmaku
        for item in drawables.subtracting(current) {
            if let layer = self.layer.sublayers?.first(where: { ($0.value(forKey: "dHash") as? Int) == item.hashValue }) {
                layer.removeFromSuperlayer()
            }
        }

        // Add new danmaku with native Core Animation
        for item in active where !drawables.contains(item) {
            let layer = CATextLayer()
            layer.string = item.text
            layer.fontSize = item.fontSize
            layer.font = UIFont.boldSystemFont(ofSize: item.fontSize)
            layer.foregroundColor = hexToCGColor(item.colorHex)
            layer.contentsScale = UIScreen.main.scale
            layer.alignmentMode = .left
            layer.isWrapped = false
            layer.setValue(item.hashValue, forKey: "dHash")

            let textWidth = (item.text as NSString).size(withAttributes: [.font: UIFont.boldSystemFont(ofSize: item.fontSize)]).width
            layer.frame = CGRect(x: bounds.width, y: item.y, width: ceil(textWidth) + 20, height: item.fontSize + 8)
            self.layer.addSublayer(layer)

            // Native Core Animation: right → left, GPU compositor thread
            let anim = CABasicAnimation(keyPath: "position.x")
            anim.fromValue = bounds.width + ceil(textWidth) / 2
            anim.toValue = -ceil(textWidth) / 2
            let remaining = max(item.duration - (now - item.startTime), 0)
            anim.duration = remaining / 1000
            anim.isRemovedOnCompletion = true
            anim.fillMode = .forwards
            layer.add(anim, forKey: "scroll")
        }

        drawables = current
    }

    private func hexToCGColor(_ hex: String) -> CGColor {
        let s = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard s.count == 6, let n = Int(s, radix: 16) else { return UIColor.white.cgColor }
        return UIColor(red: CGFloat((n >> 16) & 0xFF)/255,
                       green: CGFloat((n >> 8) & 0xFF)/255,
                       blue: CGFloat(n & 0xFF)/255, alpha: 1).cgColor
    }
}

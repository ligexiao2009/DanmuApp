import SwiftUI

@MainActor
final class DanmakuEngine: ObservableObject {
    @Published var config = DanmakuConfig()

    private var danmus: [DanmakuItem] = []
    private var danmuIndex: Int = 0
    private var activeItems: [ActiveDanmaku] = []
    private var laneAvailableAt: [Double] = []
    private var canvasSize: CGSize = .zero

    private let laneGap: Double = 24
    private let maxPerFrame: Int = 6

    struct ActiveDanmaku: Hashable {
        let text: String
        let colorHex: String
        let y: Double
        let startX: Double
        let endX: Double
        let startTime: Double
        let duration: Double
        let fontSize: Double
    }

    func load(_ items: [DanmakuItem]) {
        danmus = items.sorted { $0.time < $1.time }
        danmuIndex = 0
        activeItems.removeAll()
        laneAvailableAt.removeAll()
    }

    func append(_ items: [DanmakuItem]) {
        guard !items.isEmpty else { return }
        danmus = (danmus + items).sorted { $0.time < $1.time }
    }

    func reset() {
        danmuIndex = 0
        activeItems.removeAll()
        laneAvailableAt.removeAll()
    }

    func seek(to time: Double) {
        let target = time + config.offset
        danmuIndex = danmus.firstIndex(where: { $0.time >= target }) ?? danmus.count
        activeItems.removeAll()
        laneAvailableAt.removeAll()
    }

    func update(size: CGSize) { canvasSize = size }

    /// Call each frame with current video time. Returns the active danmaku to render.
    func tick(currentTime: Double, elapsed: TimeInterval) -> [ActiveDanmaku] {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return [] }

        let now = elapsed * 1000
        let triggerTime = currentTime + config.offset

        // Emit due danmaku
        var emitted = 0
        while danmuIndex < danmus.count && danmus[danmuIndex].time <= triggerTime {
            defer { danmuIndex += 1 }
            if emitted >= maxPerFrame { continue }
            if emit(danmus[danmuIndex], now: now) { emitted += 1 }
        }

        // Filter finished danmaku
        activeItems = activeItems.filter { now - $0.startTime < $0.duration }
        return activeItems
    }

    private func emit(_ item: DanmakuItem, now: Double) -> Bool {
        let fontSize = config.fontSize
        let text = item.text
        let textWidth = measureWidth(text: text, fontSize: fontSize)

        let availableHeight = max(fontSize, canvasSize.height * (Double(config.area) / 100.0))
        let laneHeight = fontSize + 8
        let laneCount = max(1, Int(availableHeight / laneHeight))

        if laneAvailableAt.count != laneCount {
            laneAvailableAt = Array(repeating: 0, count: laneCount)
        }

        // Find earliest free lane
        var laneIdx = 0
        var earliestTime = laneAvailableAt[0]
        var foundFree = false
        for i in 0..<laneAvailableAt.count {
            if laneAvailableAt[i] <= now { laneIdx = i; foundFree = true; break }
            if laneAvailableAt[i] < earliestTime { earliestTime = laneAvailableAt[i]; laneIdx = i }
        }
        if !foundFree && laneAvailableAt[laneIdx] > now { return false }

        let y = Double(laneIdx) * laneHeight
        let durationMs = config.speed * 1000
        let travelDistance = canvasSize.width + textWidth
        let speedPPS = travelDistance / config.speed
        let waitSeconds = (textWidth + laneGap) / speedPPS
        laneAvailableAt[laneIdx] = now + waitSeconds * 1000

        let colorHex = item.color ?? "#ffffff"
        activeItems.append(ActiveDanmaku(
            text: text,
            colorHex: colorHex,
            y: y,
            startX: canvasSize.width,
            endX: -textWidth,
            startTime: now,
            duration: durationMs,
            fontSize: fontSize
        ))
        return true
    }

    private func measureWidth(text: String, fontSize: Double) -> Double {
        let attrs = [NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: fontSize)]
        return (text as NSString).size(withAttributes: attrs).width
    }
}

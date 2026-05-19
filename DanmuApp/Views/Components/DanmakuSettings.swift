import SwiftUI

struct DanmakuSettings: View {
    @Binding var config: DanmakuConfig
    var danmakuHidden: Bool
    var onToggleDanmaku: (() -> Void)?

    var body: some View {
        NavigationStack {
            Form {
                Section("弹幕显示") {
                    LabeledSlider(label: "速度", value: $config.speed, range: 8...40, step: 1, format: "%.0fs")
                    LabeledSlider(label: "字号", value: $config.fontSize, range: 14...72, step: 1, format: "%.0fpx")
                    LabeledSlider(label: "区域", value: Binding(get: { Double(config.area) }, set: { config.area = Int($0) }), range: 10...100, step: 5, format: "%.0f%%")
                    LabeledSlider(label: "透明度", value: $config.opacity, range: 0.1...1, step: 0.05, format: "%.0f%%")
                    LabeledSlider(label: "偏移", value: $config.offset, range: -300...300, step: 1, format: "%.0fs")
                }
                Section {
                    Button {
                        onToggleDanmaku?()
                    } label: {
                        Label(danmakuHidden ? "重新开启弹幕" : "关闭所有弹幕",
                              systemImage: danmakuHidden ? "text.badge.checkmark" : "text.badge.xmark")
                    }
                    .tint(danmakuHidden ? .green : .red)
                }
            }
            .navigationTitle("弹幕设置")
        }
    }
}

struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: String

    var displayValue: String { String(format: format, value) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(displayValue).font(.caption).monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Full formatter
extension DanmakuConfig {
    func displayText(for keyPath: PartialKeyPath<DanmakuConfig>) -> String {
        switch keyPath {
        case \.speed: return String(format: "%.0f秒", speed)
        case \.fontSize: return String(format: "%.0fpx", fontSize)
        case \.area: return String(format: "%d%%", area)
        case \.opacity: return String(format: "%.0f%%", opacity * 100)
        case \.offset: return String(format: "%+.0fs", offset)
        default: return ""
        }
    }
}

import SwiftUI
import AVKit

struct LiveView: View {
    @StateObject private var engine = DanmakuEngine()
    @State private var player = AVPlayer()
    @State private var currentTime: Double = 0
    @State private var playerDuration: Double = 0
    @State private var isPlaying: Bool = false
    @State private var timeObserver: Any?
    @State private var durationObserver: NSKeyValueObservation?
    @State private var lastCurrentTime: Double = 0

    // Stream
    @State private var streamURL: String = ""
    @State private var sniffURL: String = ""
    @State private var sniffStatus: String = ""

    // Danmaku (zhibo8 / txsp only)
    @State private var selectedSource: String = "zhibo8"
    @State private var danmakuID: String = ""
    @State private var zhibo8Type: String = "nba"
    @State private var txspRoomId: String = ""
    @State private var txspProgramId: String = ""
    @State private var showSettings: Bool = false
    @State private var statusMessage: String = ""
    @State private var danmakuCount: Int = 0

    // Polling
    @State private var pollTimer: Timer?
    @State private var isPolling: Bool = false
    @State private var zhibo8LastMaxId: Int = 0
    @State private var txspLastSeq: Int = 0
    @State private var txspCursor: String = ""

    // Controls
    @State private var showControls: Bool = true
    @State private var seekTarget: Double = 0
    @State private var isDraggingSlider: Bool = false
    @State private var isFullscreen: Bool = false

    private let sources = [("zhibo8", "直播吧"), ("txsp", "腾讯体育")]
    private let zhibo8Types = [("nba", "NBA"), ("zuqiu", "足球"), ("other", "其他")]

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            Group {
                if isLandscape {
                    HStack(spacing: 0) {
                        playerArea
                        controlSidebar.frame(width: 320)
                    }
                } else {
                    VStack(spacing: 0) {
                        playerArea.frame(height: geo.size.width * 9 / 16)
                        controlSheet
                    }
                }
            }
            .ignoresSafeArea(edges: isLandscape ? .bottom : [])
        }
        .onAppear { setupTimeObserver() }
        .onDisappear { player.pause(); isPlaying = false; stopPolling(); removeTimeObserver() }
        .sheet(isPresented: $showSettings) {
            DanmakuSettings(config: $engine.config)
        }
        .fullScreenCover(isPresented: $isFullscreen) {
            LiveFullscreenView(
                player: player, engine: engine,
                currentTime: currentTime, playerDuration: playerDuration,
                isPlaying: $isPlaying, seekTarget: $seekTarget,
                isDraggingSlider: $isDraggingSlider, isFullscreen: $isFullscreen
            )
        }
    }

    // MARK: - Player

    private var playerArea: some View {
        ZStack {
            VideoPlayerView(player: .constant(player))
            DanmakuOverlay(engine: engine, currentTime: currentTime, isPlaying: isPlaying)

            if showControls {
                VStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Slider(value: $seekTarget, in: 0...max(playerDuration, 1),
                            onEditingChanged: { editing in
                                isDraggingSlider = editing
                                if !editing {
                                    Task { await player.seek(to: CMTime(seconds: seekTarget, preferredTimescale: 600)) }
                                }
                            }
                        ).tint(.red)
                        HStack {
                            Text(formatTime(currentTime)).font(.caption2).monospacedDigit()
                            Spacer()
                            Text(formatTime(playerDuration)).font(.caption2).monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial.opacity(0.6))
                }
                .transition(.opacity)
            }
        }
        .background(.black)
        .animation(.easeInOut(duration: 0.3), value: showControls)
        .overlay(alignment: .topTrailing) {
            if showControls {
                Button { isFullscreen = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.title3).padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }.padding(12)
            }
        }
        .onTapGesture {
            isPlaying ? player.pause() : player.play()
            showControls = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { showControls = false }
        }
    }

    // MARK: - Sidebar (landscape)

    private var controlSidebar: some View {
        ScrollView {
            streamControls.padding(12)
        }.background(.ultraThinMaterial)
    }

    private var controlSheet: some View {
        ScrollView {
            streamControls.padding(12)
        }.background(.regularMaterial)
    }

    // MARK: - Shared controls

    private var streamControls: some View {
        VStack(spacing: 12) {
            // --- 直播流 ---
            VStack(alignment: .leading, spacing: 6) {
                Label("直播流", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption).foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    TextField("网页地址提取...", text: $sniffURL)
                        .textFieldStyle(.roundedBorder).font(.caption)
                    Button("提取") { Task { await sniff() } }
                        .buttonStyle(.borderedProminent).tint(.indigo)                }
                if !sniffStatus.isEmpty {
                    Text(sniffStatus).font(.caption2).foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    TextField("M3U8 直播地址...", text: $streamURL)
                        .textFieldStyle(.roundedBorder).font(.caption)
                }
                HStack(spacing: 6) {
                    Button { playStream() } label: {
                        Label("播放", systemImage: "play.fill").font(.caption)
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(.red)
                    Button { stopStream() } label: {
                        Label("停止", systemImage: "stop.fill").font(.caption)
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)                }
            }

            Divider()

            // --- 弹幕 ---
            VStack(alignment: .leading, spacing: 6) {
                Label("弹幕", systemImage: "text.bubble").font(.caption).foregroundStyle(.secondary)

                Picker("弹幕源", selection: $selectedSource) {
                    ForEach(sources, id: \.0) { Text($0.1).tag($0.0) }
                }.pickerStyle(.segmented)

                if selectedSource == "zhibo8" {
                    Picker("赛事", selection: $zhibo8Type) {
                        ForEach(zhibo8Types, id: \.0) { Text($0.1).tag($0.0) }
                    }.pickerStyle(.segmented)
                }

                if selectedSource == "txsp" {
                    HStack(spacing: 6) {
                        TextField("Room ID", text: $txspRoomId)
                            .textFieldStyle(.roundedBorder).font(.caption)
                        TextField("Program ID", text: $txspProgramId)
                            .textFieldStyle(.roundedBorder).font(.caption)
                    }
                }

                HStack(spacing: 6) {
                    TextField("房间号或ID", text: $danmakuID)
                        .textFieldStyle(.roundedBorder).font(.caption)
                    Button("加载") { loadDanmakuPolling() }
                        .buttonStyle(.borderedProminent).tint(.indigo)                }

                HStack(spacing: 4) {
                    if !statusMessage.isEmpty {
                        Text(statusMessage).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text("\(danmakuCount) 条").font(.caption2).foregroundStyle(.secondary)
                }
            }

            Divider()

            // --- 播放 ---
            HStack(spacing: 6) {
                Button {
                    isPlaying ? player.pause() : player.play()
                } label: {
                    Label(isPlaying ? "暂停" : "播放", systemImage: isPlaying ? "pause.fill" : "play.fill")
                        .font(.caption).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(isPlaying ? .orange : .indigo)
                
                Button { showSettings = true } label: {
                    Label("设置", systemImage: "slider.horizontal.3").font(.caption)
                }.buttonStyle(.bordered)
                Button { engine.reset(); stopStream() } label: {
                    Label("重置", systemImage: "arrow.counterclockwise").font(.caption)
                }.buttonStyle(.bordered)            }
        }
    }

    // MARK: - Actions

    private func playStream() {
        guard !streamURL.isEmpty, let url = URL(string: streamURL) else { return }
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.play()
        isPlaying = true
    }

    private func stopStream() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
    }

    private func sniff() async {
        guard !sniffURL.isEmpty else { return }
        sniffStatus = "提取中..."
        do {
            let result = try await APIService.shared.sniffStream(pageUrl: sniffURL)
            streamURL = result.streamUrl
            sniffStatus = "已提取"
        } catch {
            sniffStatus = error.localizedDescription
        }
    }

    // MARK: - Danmaku polling

    private func loadDanmakuPolling() {
        stopPolling()
        startPolling()
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        isPolling = false
    }

    private func startPolling() {
        isPolling = true
        if selectedSource == "zhibo8" {
            guard !danmakuID.isEmpty else { return }
            zhibo8LastMaxId = 0
            engine.load([])
            statusMessage = "开始轮询..."
            pollZhibo8()
            pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                Task { @MainActor in self.pollZhibo8() }
            }
        } else if selectedSource == "txsp" {
            guard !txspRoomId.isEmpty, !txspProgramId.isEmpty else {
                statusMessage = "请输入 Room ID 和 Program ID"; return
            }
            txspLastSeq = 0
            txspCursor = ""
            engine.load([])
            statusMessage = "开始轮询..."
            pollTxsp()
        }
    }

    private func pollZhibo8() {
        Task {
            do {
                let response = try await APIService.shared.fetchZhibo8Danmaku(
                    matchId: danmakuID, type: zhibo8Type, lastMaxId: zhibo8LastMaxId
                )
                engine.append(response.danmus)
                danmakuCount += response.count
                zhibo8LastMaxId = max(zhibo8LastMaxId, response.count)
                statusMessage = "轮询中... 共 \(danmakuCount) 条"
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func pollTxsp() {
        Task {
            do {
                let response = try await APIService.shared.fetchTxspDanmaku(
                    roomId: txspRoomId, programId: txspProgramId,
                    lastSeq: txspLastSeq, cursor: txspCursor
                )
                engine.append(response.danmus)
                danmakuCount += response.count
                if response.count > 0 {
                    statusMessage = "轮询中... 共 \(danmakuCount) 条"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    Task { @MainActor in
                        guard self.isPolling else { return }
                        self.pollTxsp()
                    }
                }
            } catch {
                statusMessage = "轮询失败: \(error.localizedDescription)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    Task { @MainActor in
                        guard self.isPolling else { return }
                        self.pollTxsp()
                    }
                }
            }
        }
    }

    // MARK: - Time observer

    private func setupTimeObserver() {
        let interval = CMTime(value: 1, timescale: 10)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let t = time.seconds
            Task { @MainActor in
                if abs(t - self.lastCurrentTime) > 0.5 { self.engine.seek(to: t) }
                self.lastCurrentTime = t
                self.currentTime = t
                if !self.isDraggingSlider { self.seekTarget = t }
                self.isPlaying = self.player.rate != 0
            }
        }
    }

    private func removeTimeObserver() {
        if let obs = timeObserver { player.removeTimeObserver(obs) }
        durationObserver?.invalidate()
    }

    private func formatTime(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "--:--" }
        let h = Int(s) / 3600, m = (Int(s) % 3600) / 60, sec = Int(s) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%02d:%02d", m, sec)
    }
}

// MARK: - Live Fullscreen

struct LiveFullscreenView: View {
    let player: AVPlayer
    @ObservedObject var engine: DanmakuEngine
    let currentTime: Double, playerDuration: Double
    @Binding var isPlaying: Bool
    @Binding var seekTarget: Double
    @Binding var isDraggingSlider: Bool
    @Binding var isFullscreen: Bool

    @State private var showControls = true

    var body: some View {
        ZStack {
            VideoPlayerView(player: .constant(player))
            DanmakuOverlay(engine: engine, currentTime: currentTime, isPlaying: isPlaying)

            VStack {
                HStack {
                    Spacer()
                    Button { isFullscreen = false } label: {
                        Image(systemName: "xmark.circle.fill").font(.title2)
                            .foregroundStyle(.white).padding(10)
                            .background(.ultraThinMaterial).clipShape(Circle())
                    }
                }.padding(.horizontal, 16).padding(.top, 8)
                Spacer()
            }.opacity(showControls ? 1 : 0)

            if showControls {
                VStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Slider(value: $seekTarget, in: 0...max(playerDuration, 1),
                            onEditingChanged: { editing in
                                isDraggingSlider = editing
                                if !editing {
                                    Task { await player.seek(to: CMTime(seconds: seekTarget, preferredTimescale: 600)) }
                                }
                            }
                        ).tint(.red)
                        HStack {
                            Text(formatTime(currentTime)).font(.caption2).monospacedDigit()
                            Spacer()
                            Text(formatTime(playerDuration)).font(.caption2).monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial.opacity(0.6))
                }
                .transition(.opacity)
            }
        }
        .background(.black)
        .animation(.easeInOut(duration: 0.3), value: showControls)
        .ignoresSafeArea().statusBarHidden()
        .onTapGesture {
            isPlaying ? player.pause() : player.play()
            showControls = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { showControls = false }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { showControls = false }
        }
    }

    private func formatTime(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "--:--" }
        let h = Int(s) / 3600, m = (Int(s) % 3600) / 60, sec = Int(s) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%02d:%02d", m, sec)
    }
}

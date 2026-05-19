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
    @State private var controlsTimer: Task<Void, Never>? // 新增：可控的控制条定时器

    private let sources = [("zhibo8", "直播吧"), ("txsp", "腾讯体育")]
    private let zhibo8Types = [("nba", "NBA"), ("zuqiu", "足球"), ("other", "其他")]

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            Group {
                if isLandscape {
                    HStack(spacing: 0) {
                        playerArea
                        controlSidebar.frame(width: 350) // 拓宽侧边栏，给大屏更好的排版空间
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
        .onAppear { setupTimeObserver(); resetControlsTimer() }
        .onDisappear { player.pause(); isPlaying = false; stopPolling(); removeTimeObserver(); controlsTimer?.cancel() }
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

    // MARK: - Player Area

    private var playerArea: some View {
        ZStack {
            AVPlayerView(player: player)
            DanmakuOverlay(engine: engine, currentTime: currentTime, isPlaying: isPlaying)

            if showControls {
                VStack {
                    Spacer()
                    VStack(spacing: 4) {
                        if isDraggingSlider {
                            Text(formatTime(seekTarget))
                                .font(.title3.bold()).monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(.red, in: RoundedRectangle(cornerRadius: 8))
                        }
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
                        .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial.opacity(0.7))
                    .transition(.opacity)
                }
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
                        .foregroundColor(.white)
                }.padding(12)
            }
        }
        .onTapGesture {
            if isPlaying { player.pause() } else { player.play() }
            showControls = true
            resetControlsTimer()
        }
    }

    private func resetControlsTimer() {
        controlsTimer?.cancel()
        controlsTimer = Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000) // 8秒无操作自动隐藏
            guard !Task.isCancelled else { return }
            withAnimation { showControls = false }
        }
    }

    // MARK: - Sidebar & Sheet Container

    private var controlSidebar: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 顶部状态看版
                liveStatusHeader
                streamControls
            }
            .padding(.horizontal, 16) // 左右依然保持 16 的舒适间距
            .padding(.bottom, 16)     // 底部依然保持 16
            .padding(.top, 0)         // 👈 把顶部间距从 16 缩减到 2（或者 0），立刻大幅度上移！
        }
        .background(.ultraThinMaterial)
//        .ignoresSafeArea(edges: .top)
    }

    private var controlSheet: some View {
        ScrollView {
            VStack(spacing: 16) {
                streamControls
            }
            .padding(.horizontal, 16) // 左右依然保持 16 的舒适间距
            .padding(.bottom, 16)     // 底部依然保持 16
            .padding(.top, 2)         // 👈 把顶部间距从 16 缩减到 2（或者 0），立刻大幅度上移！
        }
        .background(.regularMaterial)
    }

    // MARK: - Live Header 看板

    private var liveStatusHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(isPlaying ? Color.red : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(isPlaying ? "正在直播" : "未连接")
                        .font(.caption2).bold()
                        .foregroundColor(isPlaying ? .red : .secondary)
                }
                Text("实时弹幕容器").font(.headline)
            }
            Spacer()
            
            Text("\(danmakuCount) 条")
                .font(.caption2).bold()
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.red.opacity(0.1), in: Capsule())
                .foregroundColor(.red)
        }
        .padding(12)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Shared Stream Controls

    private var streamControls: some View {
        VStack(spacing: 16) {
            
            // --- 模块 1：直播流配置卡片 ---
            VStack(alignment: .leading, spacing: 12) {
                Label("直播流源 (M3U8)", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.footnote).bold().foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        TextField("输入网页地址自动嗅探...", text: $sniffURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                        Button("嗅探") { Task { await sniff() } }
                            .buttonStyle(.borderedProminent)
                            .tint(.indigo)
                    }
                    
                    if !sniffStatus.isEmpty {
                        Text(sniffStatus)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                TextField("直播源绝对地址...", text: $streamURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
                
                HStack(spacing: 8) {
                    Button { playStream() } label: {
                        Label("加载播放", systemImage: "play.fill")
                            .font(.subheadline).bold()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(streamURL.isEmpty)
                    
                    Button { stopStream() } label: {
                        Label("停止", systemImage: "stop.fill")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(14)
            .background(Color.primary.opacity(0.02))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // --- 模块 2：弹幕配置卡片 ---
            VStack(alignment: .leading, spacing: 12) {
                Label("实时弹幕服务", systemImage: "text.bubble")
                    .font(.footnote).bold().foregroundStyle(.secondary)

                Picker("弹幕源", selection: $selectedSource) {
                    ForEach(sources, id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.segmented)

                if selectedSource == "zhibo8" {
                    Picker("赛事分类", selection: $zhibo8Type) {
                        ForEach(zhibo8Types, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .pickerStyle(.segmented)
                }

                if selectedSource == "txsp" {
                    HStack(spacing: 8) {
                        TextField("Room ID", text: $txspRoomId)
                            .textFieldStyle(.roundedBorder).font(.subheadline)
                        TextField("Program ID", text: $txspProgramId)
                            .textFieldStyle(.roundedBorder).font(.subheadline)
                    }
                }

                HStack(spacing: 6) {
                    TextField(selectedSource == "zhibo8" ? "房间号/比赛ID" : "视频ID", text: $danmakuID)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                    
                    Button("联机轮询") { loadDanmakuPolling() }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                }

                if !statusMessage.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle").font(.caption2)
                        Text(statusMessage).font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(Color.primary.opacity(0.02))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // --- 模块 3：底层多媒体全局快捷键 ---
            HStack(spacing: 8) {
                Button {
                    isPlaying ? player.pause() : player.play()
                } label: {
                    Label(isPlaying ? "暂停" : "开播", systemImage: isPlaying ? "pause.fill" : "play.fill")
                        .font(.subheadline).bold()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(isPlaying ? .orange : .indigo)
                
                Button { showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                
                Button { engine.reset(); stopStream() } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)

                Button { isFullscreen = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.regular)
        }
    }

    // MARK: - Core Logic & Network Actions

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
        sniffStatus = "网络探针运行中..."
        do {
            let result = try await APIService.shared.sniffStream(pageUrl: sniffURL)
            streamURL = result.streamUrl
            sniffStatus = "嗅探成功！已自动填充地址"
        } catch {
            sniffStatus = "解析失败: \(error.localizedDescription)"
        }
    }

    // MARK: - Danmaku Polling Engine

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
            statusMessage = "激活轮询监听..."
            pollZhibo8()
            pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                Task { @MainActor in self.pollZhibo8() }
            }
        } else if selectedSource == "txsp" {
            guard !txspRoomId.isEmpty, !txspProgramId.isEmpty else {
                statusMessage = "房间参数缺失"; return
            }
            txspLastSeq = 0
            txspCursor = ""
            engine.load([])
            statusMessage = "激活轮询监听..."
            pollTxsp()
        }
    }

    private func pollZhibo8() {
        Task {
            do {
                let response = try await APIService.shared.fetchZhibo8Danmaku(
                    matchId: danmakuID, type: zhibo8Type, lastMaxId: zhibo8LastMaxId
                )
                if response.count > 0 {
                    engine.append(response.danmus)
                    danmakuCount = engine.danmusCount
                }
                if let maxId = response.maxId { zhibo8LastMaxId = maxId }
                statusMessage = "同步完成，通道运行正常"
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
                if response.count > 0 {
                    engine.append(response.danmus)
                    danmakuCount = engine.danmusCount
                }
                if let maxSeq = response.maxSeq { txspLastSeq = maxSeq }
                if let cursor = response.cursor { txspCursor = cursor }
                let interval = Double(response.pullInterval ?? 3000) / 1000.0
                DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                    Task { @MainActor in
                        guard self.isPolling else { return }
                        self.pollTxsp()
                    }
                }
            } catch {
                statusMessage = "重试连接中..."
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    Task { @MainActor in
                        guard self.isPolling else { return }
                        self.pollTxsp()
                    }
                }
            }
        }
    }

    // MARK: - Time Observers

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

// MARK: - Live Fullscreen View

struct LiveFullscreenView: View {
    let player: AVPlayer
    @ObservedObject var engine: DanmakuEngine
    let currentTime: Double, playerDuration: Double
    @Binding var isPlaying: Bool
    @Binding var seekTarget: Double
    @Binding var isDraggingSlider: Bool
    @Binding var isFullscreen: Bool

    @State private var showControls = true
    @State private var controlsTimer: Task<Void, Never>? // 同样升级全屏定时器

    var body: some View {
        ZStack {
            AVPlayerView(player: player)
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
                        if isDraggingSlider {
                            Text(formatTime(seekTarget))
                                .font(.title3.bold()).monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(.red, in: RoundedRectangle(cornerRadius: 8))
                        }
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
                        .foregroundColor(.white)
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
            if isPlaying { player.pause() } else { player.play() }
            showControls = true
            resetControlsTimer()
        }
        .onAppear { resetControlsTimer() }
        .onDisappear { controlsTimer?.cancel() }
    }

    private func resetControlsTimer() {
        controlsTimer?.cancel()
        controlsTimer = Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { showControls = false }
        }
    }

    private func formatTime(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "--:--" }
        let h = Int(s) / 3600, m = (Int(s) % 3600) / 60, sec = Int(s) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%02d:%02d", m, sec)
    }
}

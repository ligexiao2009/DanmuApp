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
    @AppStorage("live_streamURL") private var streamURL: String = ""
    @State private var sniffURL: String = ""
    @State private var txspPageURL: String = ""
    @State private var sniffStatus: String = ""
    @State private var txspSniffStatus: String = ""

    // Danmaku (zhibo8 / txsp only)
    @AppStorage("live_source") private var selectedSource: String = "zhibo8"
    @AppStorage("live_matchId") private var danmakuID: String = ""
    @AppStorage("live_zhibo8Type") private var zhibo8Type: String = "nba"
    @AppStorage("live_txspRoomId") private var txspRoomId: String = ""
    @AppStorage("live_txspProgramId") private var txspProgramId: String = ""
    @AppStorage("live_txspCookie") private var txspCookie: String = ""
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
    @State private var showSidebar: Bool = true
    @State private var keyboardHeight: CGFloat = 0
    @State private var controlsTimer: Task<Void, Never>?

    private let sources = [("zhibo8", "直播吧"), ("txsp", "腾讯体育")]
    private let zhibo8Types = [("nba", "NBA"), ("zuqiu", "足球"), ("other", "其他")]

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            Group {
                if isLandscape {
                    HStack(spacing: 0) {
                        playerArea
                        if showSidebar { controlSidebar.frame(width: 350) }
                    }
                    .overlay(alignment: .topTrailing) {
                        if !showSidebar {
                            Button { withAnimation { showSidebar.toggle() } } label: {
                                Image(systemName: "sidebar.left")
                                    .font(.title3).padding(10)
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }.padding(12)
                        }
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
        .onAppear {
            setupTimeObserver()
            resetControlsTimer()
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { n in
                keyboardHeight = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height ?? 0
            }
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
                keyboardHeight = 0
            }
        }
        .onDisappear {
            player.pause()
            isPlaying = false
            stopPolling()
            removeTimeObserver()
            controlsTimer?.cancel()
        }
        .sheet(isPresented: $showSettings) {
            DanmakuSettings(config: $engine.config, danmakuHidden: false, onToggleDanmaku: { engine.load([]) })
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
                                    Task {
                                        await player.seek(to: CMTime(seconds: seekTarget, preferredTimescale: 600))
                                        // 确保拖拽结束同步真实当前时间
                                        currentTime = seekTarget
                                    }
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
            // 优化：单键点击仅处理控制条显隐，不粗暴打断视频播放
            withAnimation { showControls.toggle() }
            if showControls { resetControlsTimer() }
        }
    }

    private func resetControlsTimer() {
        controlsTimer?.cancel()
        controlsTimer = Task {
            try? await Task.sleep(for: .seconds(8)) // 规避旧版纳秒警告
            guard !Task.isCancelled else { return }
            withAnimation { showControls = false }
        }
    }

    // MARK: - Sidebar & Sheet Container

    private var controlSidebar: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Button { withAnimation { showSidebar.toggle() } } label: {
                        Image(systemName: "sidebar.right").font(.body)
                    }
                }
                liveStatusHeader
                streamControls
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .padding(.top, 2)
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: keyboardHeight) }
        .background(.ultraThinMaterial)
    }

    private var controlSheet: some View {
        ScrollView {
            VStack(spacing: 16) {
                streamControls
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .padding(.top, 2)
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
                    HStack(spacing: 6) {
                        TextField("腾讯体育直播页地址...", text: $txspPageURL)
                            .textFieldStyle(.roundedBorder).font(.caption)
                        Button("提取") { Task { await sniffTxspCookie() } }
                            .buttonStyle(.borderedProminent).tint(.orange).controlSize(.small)
                    }
                    if !txspSniffStatus.isEmpty {
                        Text(txspSniffStatus).font(.caption2).foregroundStyle(.secondary)
                    }
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
                    isPlaying.toggle()
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
        let item = AVPlayerItem(url: url)
        
        // 挂载 KVO 监听视频总长度
        durationObserver = item.observe(\.status, options: [.new]) { [self] item, _ in
            if item.status == .readyToPlay {
                let duration = item.duration.seconds
                if duration.isFinite && duration > 0 {
                    self.playerDuration = duration
                }
            }
        }
        
        player.replaceCurrentItem(with: item)
        player.play()
        isPlaying = true
    }

    private func stopStream() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        durationObserver?.invalidate()
        durationObserver = nil
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

    private func sniffTxspCookie() async {
        guard !txspPageURL.isEmpty else { return }
        txspSniffStatus = "提取中..."
        do {
            let result = try await APIService.shared.sniffTxsp(pageUrl: txspPageURL)
            txspRoomId = result.roomId
            txspProgramId = result.programId
            if let cookie = result.cookie { txspCookie = cookie }
            txspSniffStatus = "已提取 Room \(result.roomId)"
        } catch {
            txspSniffStatus = error.localizedDescription
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
            scheduleTxspTimer()
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
                    lastSeq: txspLastSeq, cursor: txspCursor, cookie: txspCookie
                )
                if response.count > 0 {
                    engine.append(response.danmus)
                    danmakuCount = engine.danmusCount
                }
                if let maxSeq = response.maxSeq { txspLastSeq = maxSeq }
                if let cursor = response.cursor { txspCursor = cursor }
                statusMessage = "同步完成，通道运行正常"
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func scheduleTxspTimer() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in
                guard self.isPolling else { return }
                self.pollTxsp()
            }
        }
    }

    // MARK: - Time Observers

    private func setupTimeObserver() {
        let interval = CMTime(value: 1, timescale: 10)
        // 引入 [self] 防止内存泄漏
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [self] time in
            // 如果用户正在拖拽进度条，直接阻断来自播放器的自动更新，防止进度条“打架”
            guard !self.isDraggingSlider else { return }
            
            let t = time.seconds
            if abs(t - self.lastCurrentTime) > 0.5 { self.engine.seek(to: t) }
            self.lastCurrentTime = t
            self.currentTime = t
            self.seekTarget = t
            self.isPlaying = self.player.rate != 0
        }
    }

    private func removeTimeObserver() {
        if let obs = timeObserver { player.removeTimeObserver(obs) }
        timeObserver = nil
        durationObserver?.invalidate()
        durationObserver = nil
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
    @State private var controlsTimer: Task<Void, Never>?

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
            withAnimation { showControls.toggle() }
            if showControls { resetControlsTimer() }
        }
        .onAppear { resetControlsTimer() }
        .onDisappear { controlsTimer?.cancel() }
    }

    private func resetControlsTimer() {
        controlsTimer?.cancel()
        controlsTimer = Task {
            try? await Task.sleep(for: .seconds(6))
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

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
    @State private var txspPollTask: Task<Void, Never>?

    // Controls
    @State private var showControls: Bool = true
    @State private var seekTarget: Double = 0
    @State private var isDraggingSlider: Bool = false
    @State private var isFullscreen: Bool = false
    @State private var showSidebar: Bool = true
    @State private var keyboardHeight: CGFloat = 0
    @State private var controlsTimer: Task<Void, Never>?
    
    // Animation triggers
    @State private var connectTrigger: Int = 0

    private let sources = [("zhibo8", "直播吧"), ("txsp", "腾讯体育")]
    private let zhibo8Types = [("nba", "NBA"), ("zuqiu", "足球"), ("other", "其他")]

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height

            Group {
                if isLandscape {
                    HStack(spacing: 0) {
                        playerArea
                        if showSidebar { controlSidebar.frame(width: 360) }
                    }
                    .overlay(alignment: .topTrailing) {
                        if !showSidebar {
                            Button { withAnimation { showSidebar.toggle() } } label: {
                                Image(systemName: "sidebar.left")
                                    .font(.title3).padding(10)
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .foregroundColor(.white)
                            }.padding(12)
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        playerArea
                            .frame(height: geo.size.width * 9 / 16)
                            .zIndex(1)
                        portraitControls
                            .zIndex(0)
                    }
                    .ignoresSafeArea(.keyboard)
                }
            }
            .ignoresSafeArea(edges: isLandscape ? .bottom : [])
        }
        .onAppear {
            setupTimeObserver()
            resetControlsTimer()
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { n in
                let h = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height ?? 0
                if abs(h - keyboardHeight) > 1 { keyboardHeight = h }
            }
            NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
                if keyboardHeight > 0 { keyboardHeight = 0 }
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
                    .background(
                        LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .top)
                    )
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
            withAnimation { showControls.toggle() }
            if showControls { resetControlsTimer() }
        }
    }

    private func resetControlsTimer() {
        controlsTimer?.cancel()
        controlsTimer = Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { showControls = false }
        }
    }

    // MARK: - Landscape Sidebar

    private var controlSidebar: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Button { withAnimation { showSidebar.toggle() } } label: {
                        Image(systemName: "sidebar.right").font(.body).foregroundColor(.primary)
                    }
                }
                liveStatusHeader
                
                HStack(spacing: 12) {
                    Button {
                        isPlaying ? player.pause() : player.play()
                        isPlaying.toggle()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .foregroundColor(isPlaying ? .orange : .red)
                            .frame(width: 20)
                    }
                    
                    Button { engine.reset(); stopStream() } label: {
                        Label("重置", systemImage: "arrow.counterclockwise")
                    }
                    
                    Button { showSettings = true } label: {
                        Label("设置", systemImage: "slider.horizontal.3")
                    }

                    Button { isFullscreen = true } label: {
                        Label("全屏", systemImage: "arrow.up.left.and.arrow.down.right")
                    }

                    Spacer()
                }
                .font(.footnote)
                .buttonStyle(.bordered)
                .controlSize(.regular)
                
                streamSetupCard
                danmakuSetupCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: keyboardHeight) }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    // MARK: - Portrait Mobile Controls

    private var portraitControls: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. 直播状态看板
                liveStatusHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                // 2. 核心控制行（一字排开）
                HStack {
                    portraitControlButton(icon: isPlaying ? "pause.fill" : "play.fill", title: isPlaying ? "暂停" : "开播", color: isPlaying ? .orange : .red, isProminent: true) {
                        isPlaying ? player.pause() : player.play()
                        isPlaying.toggle()
                    }
                    
                    Spacer()
                    
                    portraitControlButton(icon: "arrow.counterclockwise", title: "重置流", color: .primary) {
                        engine.reset()
                        stopStream()
                    }
                    
                    Spacer()
                    
                    portraitControlButton(icon: "slider.horizontal.3", title: "弹幕设置") { showSettings = true }
                    
                    Spacer()
                    
                    portraitControlButton(icon: "arrow.up.left.and.arrow.down.right", title: "全屏") {
                        isFullscreen = true
                    }
                }
                .padding(.horizontal, 30)

                // 3. 设置卡片区
                VStack(spacing: 16) {
                    streamSetupCard
                    danmakuSetupCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }
    
    // 手机端专用快捷按钮构造器
    private func portraitControlButton(icon: String, title: String, color: Color = .primary, isProminent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(isProminent ? .title2 : .title3)
                    .foregroundColor(isProminent ? .white : color)
                    .frame(width: isProminent ? 52 : 44, height: isProminent ? 52 : 44)
                    .background(isProminent ? color : Color.clear, in: Circle())
                
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.primary)
            }
        }
    }

    // MARK: - Live Dashboard Header

    private var liveStatusHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(isPlaying ? Color.red : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(isPlaying ? "LIVE 正在播放" : "流未连接")
                        .font(.caption).bold()
                        .foregroundColor(isPlaying ? .red : .secondary)
                }
                Text(streamURL.isEmpty ? "未配置直播源" : (URL(string: streamURL)?.host ?? "自定义直播流"))
                    .font(.subheadline).bold()
                    .lineLimit(1)
            }
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(danmakuCount)")
                    .font(.headline).bold().monospacedDigit()
                    .foregroundColor(.indigo)
                Text("实时弹幕")
                    .font(.caption2).foregroundColor(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Stream & Danmaku Setup Cards

    private var streamSetupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("流媒体设置 (M3U8)", systemImage: "antenna.radiowaves.left.and.right")
                .font(.subheadline).bold().foregroundStyle(.primary)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    TextField("输入网页地址进行自动嗅探", text: $sniffURL)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                        .padding(10)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                    
                    Button { Task { await sniff() } } label: {
                        Text("嗅探").font(.subheadline).bold()
                            .padding(.horizontal, 14).padding(.vertical, 10)
                    }
                    .background(Color.indigo, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundColor(.white)
                }
                
                if !sniffStatus.isEmpty {
                    Text(sniffStatus).font(.caption2).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            VStack(spacing: 8) {
                TextField("M3U8 绝对地址", text: $streamURL)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .padding(10)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                
                HStack(spacing: 12) {
                    Button { playStream() } label: {
                        Label("加载播放", systemImage: "play.tv.fill")
                            .font(.subheadline).bold()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .background(streamURL.isEmpty ? Color.gray.opacity(0.3) : Color.red, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundColor(streamURL.isEmpty ? .secondary : .white)
                    .disabled(streamURL.isEmpty)
                    
                    Button { stopStream() } label: {
                        Image(systemName: "stop.fill")
                            .font(.subheadline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundColor(.primary)
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var danmakuSetupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("弹幕服务连接", systemImage: "text.bubble.fill")
                .font(.subheadline).bold().foregroundStyle(.primary)

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
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("腾讯体育直播页URL提取", text: $txspPageURL)
                            .textFieldStyle(.plain).font(.caption)
                            .padding(10)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                        Button { Task { await sniffTxspCookie() } } label: {
                            Text("提取").font(.caption).bold()
                                .padding(.horizontal, 12).padding(.vertical, 10)
                        }
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundColor(.white)
                    }
                    if !txspSniffStatus.isEmpty {
                        Text(txspSniffStatus).font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        TextField("Room ID", text: $txspRoomId)
                            .textFieldStyle(.plain).font(.subheadline)
                            .padding(10)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                        TextField("Program ID", text: $txspProgramId)
                            .textFieldStyle(.plain).font(.subheadline)
                            .padding(10)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            HStack(spacing: 8) {
                TextField(selectedSource == "txsp" ? "粘贴 JSON 自动解析 Room/Program/Cookie..." : (selectedSource == "zhibo8" ? "输入房间号或比赛ID" : "视频ID"), text: $danmakuID)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .padding(10)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                    .onChange(of: danmakuID) { _ in parsePastedTxspJSON() }
                
                Button { 
                    connectTrigger += 1
                    loadDanmakuPolling() 
                } label: {
                    Label(isPolling ? "监听中" : "连接", systemImage: isPolling ? "waveform.path.ecg" : "link")
                        .font(.subheadline).bold()
                        .symbolEffect(.bounce, value: connectTrigger)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                }
                .background(isPolling ? Color.green : Color.indigo, in: RoundedRectangle(cornerRadius: 8))
                .foregroundColor(.white)
            }

            if !statusMessage.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill").font(.caption)
                    Text(statusMessage).font(.caption2)
                }
                .foregroundStyle(isPolling ? .green : .secondary)
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Core Logic & Network Actions

    private func playStream() {
        guard !streamURL.isEmpty, let url = URL(string: streamURL) else { return }
        let item = AVPlayerItem(url: url)
        
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

    private func parsePastedTxspJSON() {
        guard selectedSource == "txsp" else { return }
        let raw = danmakuID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.contains("room_id") || raw.contains("program_id") else { return }

        // 优先用 JSONSerialization 解析，避免手写正则截断超长 cookie
        if let data = raw.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let r = json["room_id"] as? Int { txspRoomId = String(r) }
            else if let r = json["room_id"] as? String { txspRoomId = r }
            if let p = json["program_id"] as? String { txspProgramId = p }
            else if let p = json["program_id"] as? Int { txspProgramId = String(p) }
            if let c = json["cookie"] as? String, !c.isEmpty { txspCookie = c }
        } else {
            // 回退：正则提取
            func extract(_ key: String) -> String? {
                let pattern = "\"\(key)\"\\s*:\\s*\"?([^\",}]+)\"?"
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let m = regex.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
                      m.numberOfRanges > 1,
                      let r = Range(m.range(at: 1), in: raw) else { return nil }
                return String(raw[r]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
            if let r = extract("room_id") { txspRoomId = r }
            if let p = extract("program_id") { txspProgramId = p }
            if let cookieRange = raw.range(of: "\"cookie\"") {
                let after = raw[cookieRange.upperBound...]
                if let colon = after.firstIndex(of: ":"),
                   let open = after[colon...].firstIndex(of: "\"") {
                    let start = raw.index(after: open)
                    if let close = raw[start...].firstIndex(of: "\"") {
                        let cookie = String(raw[start..<close])
                        if !cookie.isEmpty { txspCookie = cookie }
                    }
                }
            }
        }

        guard !txspRoomId.isEmpty || !txspProgramId.isEmpty else { return }
        danmakuID = ""
        statusMessage = "已解析 Room \(txspRoomId) Program \(txspProgramId) Cookie(\(txspCookie.count)字符)"
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
        txspPollTask?.cancel()
        txspPollTask = nil
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
            scheduleTxspLoop()
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

    private func pollTxsp() async -> Int {
        do {
            let response = try await APIService.shared.fetchTxspDanmaku(
                roomId: txspRoomId, programId: txspProgramId,
                lastSeq: txspLastSeq, cursor: txspCursor, cookie: txspCookie
            )
            if response.count > 0 {
                engine.append(response.danmus)
                danmakuCount = engine.danmusCount
            }
            if let maxSeq = response.maxSeq, maxSeq > txspLastSeq { txspLastSeq = maxSeq }
            if let cursor = response.cursor, !cursor.isEmpty { txspCursor = cursor }
            statusMessage = "同步完成，通道运行正常"
            return response.pullInterval ?? 3000
        } catch {
            statusMessage = error.localizedDescription
            return 5000
        }
    }

    private func scheduleTxspLoop() {
        txspPollTask?.cancel()
        txspPollTask = Task { @MainActor in
            while isPolling && !Task.isCancelled {
                let interval = await pollTxsp()
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000)
            }
        }
    }

    // MARK: - Time Observers

    private func setupTimeObserver() {
        let interval = CMTime(value: 1, timescale: 10)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [self] time in
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
                    .background(
                        LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .top)
                    )
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
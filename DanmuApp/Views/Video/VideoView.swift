import SwiftUI
import CoreMedia
import KSPlayer

struct VideoView: View {
    @StateObject private var engine = DanmakuEngine()
    @State private var playerLayer: KSPlayerLayer?
    @State private var currentTime: Double = 0.0
    @State private var playerDuration: Double = 0.0
    @State private var isPlaying: Bool = false
    @State private var seekTarget: Double = 0
    @State private var isDraggingSlider: Bool = false
    @State private var showControls: Bool = true
    @State private var controlsTimer: Task<Void, Never>?
    @State private var isFullscreen: Bool = false
    private var playerDelegate = PlayerDelegate()
    @State private var timeObserver: Any?
    @State private var lastCurrentTime: Double = 0
    @State private var progressSaveTimer: Timer?
    @State private var videoEndedObserver: Any?

    @State private var playlist: [VideoItem] = []
    @State private var currentIndex: Int = 0

    @State private var folders: [FolderItem] = []
    @State private var selectedFolder: String = ""

    @State private var selectedSource: String = "bili"
    @State private var danmakuID: String = ""
    @State private var showSettings: Bool = false
    @State private var showFolderPicker: Bool = false
    @State private var isLoadingVideos: Bool = false
    @State private var showSidebar: Bool = true
    @State private var statusMessage: String = ""
    @State private var autoplay: Bool = true

    // Subtitles
    @State private var showSubtitlePicker = false
    @State private var serverSubtitles: [String] = []
    @State private var isLoadingSubtitles = false
    @State private var currentSubtitleName = ""
    @State private var danmakuHidden = false
    @State private var subtitleEntries: [SubtitleEntry] = []

    struct SubtitleEntry {
        let start: Double
        let end: Double
        let text: String
    }

    private let sources = [
        ("bili", "B站"), ("qq", "腾讯"), ("mango", "芒果"), ("iqiyi", "爱奇艺")
    ]

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            let sidebarWidth: CGFloat = 360

            HStack(spacing: 0) {
                // 全屏时，播放器区域直接占满全屏
                playerArea(isLandscape: isLandscape)
                    .ignoresSafeArea(edges: isFullscreen ? .all : [])
                
                if isLandscape && showSidebar && !isFullscreen {
                    sidebarView
                        .frame(width: sidebarWidth)
                        .transition(.move(edge: .trailing))
                }
            }
            .ignoresSafeArea(edges: (isLandscape || isFullscreen) ? .bottom : [])
            .safeAreaPadding(.top, (isLandscape && !isFullscreen) ? 8 : 0)
            .overlay(alignment: .bottom) {
                if !isLandscape && !isFullscreen { portraitControls }
            }
        }
        .onAppear { Task { await loadFolders(); setupTimeObserver() } }
        .onDisappear { playerLayer?.pause(); isPlaying = false; saveProgress(); removeTimeObserver(); controlsTimer?.cancel() }
        .sheet(isPresented: $showSettings) {
            DanmakuSettings(config: $engine.config, danmakuHidden: danmakuHidden, onToggleDanmaku: {
                danmakuHidden.toggle()
                if danmakuHidden {
                    engine.load([])
                    statusMessage = "弹幕已关闭"
                } else {
                    Task { await loadDanmaku() }
                    statusMessage = "弹幕重新开启"
                }
            })
        }
        .sheet(isPresented: $showFolderPicker) {
            folderPickerSheet
                .onAppear { Task { await loadFolders() } }
        }
        .sheet(isPresented: $showSubtitlePicker) {
            subtitlePickerSheet
        }
        .toolbar(isFullscreen ? .hidden : .visible, for: .tabBar)
    }

    // MARK: - Player Area

    private func playerArea(isLandscape: Bool) -> some View {
        ZStack {
            VideoPlayerView(playerLayer: $playerLayer)
            DanmakuOverlay(engine: engine, currentTime: currentTime, isPlaying: isPlaying)

            // ✨ 优化：独立的全局字幕层！
            // 把字幕放在控制面板之外，保证即使面板隐藏了，字幕依然丝滑显示
            if !currentSubtitleName.isEmpty, let text = currentSubtitleText(at: currentTime), !text.isEmpty {
                VStack {
                    Spacer()
                    Text(text)
                        .font(.system(size: isFullscreen ? 26 : 22, weight: .bold)) // 全屏时字体稍微放大
                        .foregroundColor(.white)
                        // 经典电影双层阴影特效，无论画面多白都能清晰看清字幕
                        .shadow(color: .black.opacity(0.8), radius: 1, x: 1, y: 1)
                        .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 0)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.bottom, showControls ? 80 : 30) // 如果控制栏显示，字幕上浮避开进度条
                        .animation(.easeInOut(duration: 0.2), value: showControls)
                }
                .allowsHitTesting(false) // 让点击事件穿透字幕
            }

            // 控制面板层
            if isFullscreen {
                fullscreenControlsView
            } else if showControls {
                normalControlsView
            }
        }
        .background(.black)
        .animation(.easeInOut(duration: 0.3), value: showControls)
        .overlay(alignment: .topTrailing) {
            if !isFullscreen {
                VStack(spacing: 8) {
                    if (showControls || (isLandscape && showSidebar)) {
                        Button { withAnimation { isFullscreen = true } } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.title3)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    if isLandscape && !showSidebar {
                        Button {
                            withAnimation { showSidebar.toggle() }
                        } label: {
                            Image(systemName: "sidebar.left")
                                .font(.title3)
                                .padding(10)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding(12)
            }
        }
        .onTapGesture {
            withAnimation {
                showControls.toggle()
            }
            if showControls {
                resetControlsTimer()
            }
        }
        .statusBarHidden(isFullscreen)
    }
    
    // MARK: - Normal Controls View
    
    private var normalControlsView: some View {
        VStack {
            Spacer()
            VStack(spacing: 4) {
                if isDraggingSlider {
                    Text(formatTime(seekTarget))
                        .font(.title3.bold()).monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.indigo, in: RoundedRectangle(cornerRadius: 8))
                        .transition(.opacity.combined(with: .scale(scale: 1.1)))
                }
                Slider(
                    value: $seekTarget,
                    in: 0...max(playerDuration, 1),
                    onEditingChanged: { editing in
                        isDraggingSlider = editing
                        if !editing {
                            playerLayer?.seek(time: seekTarget, autoPlay: true) { _ in }
                        }
                    }
                )
                .tint(.indigo)
                HStack {
                    Text(formatTime(currentTime)).font(.caption2).monospacedDigit()
                    Spacer()
                    Text(formatTime(playerDuration)).font(.caption2).monospacedDigit()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .top)
            ) // 优化：改用底部渐变黑影，不生硬
        }
        .transition(.opacity)
    }

    // MARK: - Fullscreen Controls View
    
    private var fullscreenControlsView: some View {
        Group {
            if showControls {
                ZStack {
                    // 全屏退出按钮（右上角）
                    VStack {
                        HStack {
                            Spacer()
                            Button {
                                withAnimation { isFullscreen = false }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2).foregroundStyle(.white)
                                    .padding(10).background(.ultraThinMaterial).clipShape(Circle())
                            }
                        }
                        .padding(16)
                        Spacer()
                    }
                    
                    // 全屏中央播放/暂停按钮
                    Button {
                        isPlaying ? playerLayer?.pause() : playerLayer?.play()
                    } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.8))
                            .shadow(radius: 5)
                    }

                    // 全屏底部进度条
                    VStack {
                        Spacer()
                        VStack(spacing: 4) {
                            if isDraggingSlider {
                                Text(formatTime(seekTarget))
                                    .font(.title3.bold()).monospacedDigit().foregroundStyle(.white)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(.indigo, in: RoundedRectangle(cornerRadius: 8))
                            }
                            Slider(value: $seekTarget, in: 0...max(playerDuration, 1),
                                onEditingChanged: { editing in
                                    isDraggingSlider = editing
                                    if !editing {
                                        playerLayer?.seek(time: seekTarget, autoPlay: true) { _ in }
                                    }
                                }
                            ).tint(.indigo)
                            HStack {
                                Text(formatTime(currentTime)).font(.caption2).monospacedDigit().foregroundColor(.white)
                                Spacer()
                                Text(formatTime(playerDuration)).font(.caption2).monospacedDigit().foregroundColor(.white)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(
                            LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .top)
                        )
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    private func resetControlsTimer() {
        controlsTimer?.cancel()
        controlsTimer = Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { showControls = false }
        }
    }

    // MARK: - Sidebar (Landscape Optimized)

    private var sidebarView: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let current = currentItem {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("正在播放")
                                .font(.caption2).bold()
                                .foregroundStyle(.indigo)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                            
                            Text(current.name.replacingOccurrences(of: "\\.[^.]+$", with: "", options: .regularExpression))
                                .font(.subheadline).bold()
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.03))
                }

                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Menu {
                            ForEach(sources, id: \.0) { src in
                                Button(src.1) { selectedSource = src.0 }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(sources.first(where: { $0.0 == selectedSource })?.1 ?? "B站")
                                Image(systemName: "chevron.down").font(.caption2)
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)

                        TextField("输入连接ID (BV/ep/VID)...", text: $danmakuID)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                            .submitLabel(.search)
                            .onSubmit { Task { await loadDanmaku() } }
                        
                        Button { Task { await loadDanmaku() } } label: {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.title2)
                        }
                        .tint(.indigo)
                        .disabled(danmakuID.isEmpty)
                    }

                    HStack(spacing: 12) {
                        Button {
                            isPlaying ? playerLayer?.pause() : playerLayer?.play()
                        } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.body)
                                .foregroundColor(isPlaying ? .orange : .indigo)
                        }
                        
                        Button { engine.seek(to: currentTime) } label: {
                            Label("同步", systemImage: "arrow.triangle.2.circlepath")
                        }
                        
                        Button { showSettings = true } label: {
                            Label("参数", systemImage: "slider.horizontal.3")
                        }

                        Button { Task { await fetchSubtitles() } } label: {
                            Label(currentSubtitleName.isEmpty ? "字幕" : "字幕✓", systemImage: "doc.text")
                                .foregroundColor(currentSubtitleName.isEmpty ? .primary : .green) // 有字幕时高亮
                        }

                        Spacer()
                    }
                    .font(.footnote)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                playlistHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                playlistList
            }
            .background(.ultraThinMaterial)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showFolderPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.indigo)
                            Text(selectedFolderName)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation { showSidebar.toggle() }
                    } label: {
                        Image(systemName: "sidebar.right")
                            .foregroundColor(.indigo)
                    }
                }
            }
        }
    }

    var selectedFolderName: String {
        if selectedFolder.isEmpty { return "选择目录" }
        return folders.first(where: { $0.path == selectedFolder })?.name ?? selectedFolder
    }

    // MARK: - Portrait Bottom Controls

    private var portraitControls: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Button {
                        showFolderPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill").font(.caption)
                            Text(selectedFolderName).font(.caption).lineLimit(1)
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                    Spacer()
                }

                Picker("弹幕源", selection: $selectedSource) {
                    ForEach(sources, id: \.0) { src in Text(src.1).tag(src.0) }
                }.pickerStyle(.segmented)

                HStack(spacing: 6) {
                    TextField("BV号 / ep号 / VID", text: $danmakuID)
                        .textFieldStyle(.roundedBorder).font(.caption)
                    Button("加载") { Task { await loadDanmaku() } }
                        .buttonStyle(.borderedProminent).tint(.indigo)
                }

                HStack(spacing: 6) {
                    Button { isPlaying ? playerLayer?.pause() : playerLayer?.play() } label: {
                        Label(isPlaying ? "暂停" : "播放", systemImage: isPlaying ? "pause.fill" : "play.fill").font(.caption)
                    }
                    .buttonStyle(.borderedProminent).tint(isPlaying ? .orange : .indigo)
                    Button { showSettings = true } label: {
                        Label("设置", systemImage: "slider.horizontal.3").font(.caption)
                    }.buttonStyle(.bordered)
                    Button { engine.seek(to: currentTime) } label: {
                        Label("同步", systemImage: "arrow.triangle.2.circlepath").font(.caption)
                    }.buttonStyle(.bordered)
                    Button { withAnimation { isFullscreen = true } } label: {
                        Label("全屏", systemImage: "arrow.up.left.and.arrow.down.right").font(.caption)
                    }.buttonStyle(.bordered)
                    Button { Task { await fetchSubtitles() } } label: {
                        Label(currentSubtitleName.isEmpty ? "字幕" : "字幕✓", systemImage: "doc.text").font(.caption)
                            .foregroundColor(currentSubtitleName.isEmpty ? .primary : .green)
                    }.buttonStyle(.bordered)
                    Spacer()

                    Toggle("连播", isOn: $autoplay).toggleStyle(.switch)
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage).font(.caption2).foregroundStyle(.secondary).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            if !playlist.isEmpty {
                playlistList.frame(maxHeight: 180)
            }
        }
        .background(.regularMaterial)
    }

    // MARK: - Folder Picker & Lists

    private var folderPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(folders) { f in
                    Button {
                        Task {
                            isLoadingVideos = true
                            await switchFolder(f.path)
                            selectedFolder = f.path
                            isLoadingVideos = false
                            showFolderPicker = false
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: f.path == selectedFolder ? "folder.fill" : "folder")
                                .font(.title3)
                                .foregroundStyle(.indigo)
                                .frame(width: 32)
                            Text(f.name)
                                .font(.body)
                            Spacer()
                            if f.path == selectedFolder {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.indigo)
                                    .font(.title3)
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    .foregroundColor(.primary)
                    .disabled(isLoadingVideos)
                }
            }
            .listStyle(.plain)
            .navigationTitle("选择目录")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if isLoadingVideos {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView("加载视频列表...")
                        .padding(20)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showFolderPicker = false }
                        .disabled(isLoadingVideos)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await loadFolders() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }

    private var playlistHeader: some View {
        HStack {
            Text("播放列表").font(.footnote.bold()).foregroundColor(.secondary)
            Spacer()
            Text("\(playlist.count) 个视频").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var playlistList: some View {
        Group {
            if playlist.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray").font(.body).foregroundStyle(.secondary)
                    Text("选择目录加载视频").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 20)
            } else {
                List {
                    ForEach(Array(playlist.enumerated()), id: \.element.id) { idx, item in
                        PlaylistRow(
                            item: item,
                            isActive: idx == currentIndex,
                            onTap: { playItem(at: idx) },
                            onDelete: { deleteItem(at: idx) }
                        )
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Core Logic & Actions

    private var currentItem: VideoItem? {
        guard currentIndex >= 0, currentIndex < playlist.count else { return nil }
        return playlist[currentIndex]
    }

    private func loadFolders() async {
        do {
            folders = try await APIService.shared.fetchFolders()
            if folders.isEmpty {
                statusMessage = "服务器未配置视频目录"
            } else if selectedFolder.isEmpty, let fallback = folders.first(where: { $0.name == "食贫道" }) ?? folders.first {
                selectedFolder = fallback.path
                await switchFolder(fallback.path)
            }
        } catch {
            statusMessage = "服务器连接失败: \(error.localizedDescription)"
        }
    }

    private func switchFolder(_ dir: String) async {
        do {
            try await APIService.shared.setVideoDir(dir)
            let names = try await APIService.shared.fetchVideos()
            playlist = names.map { name in
                VideoItem(name: name, relativePath: name, videoId: detectVideoID(name), thumbnailName: name, isRemote: true)
            }
            currentIndex = 0
            statusMessage = "已加载 \(playlist.count) 个视频"
            if !playlist.isEmpty { playItem(at: 0) }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func playItem(at index: Int) {
        guard index < playlist.count else { return }
        saveProgress()
        engine.reset()
        currentIndex = index
        let item = playlist[index]
        lastCurrentTime = 0
        currentTime = 0
        seekTarget = 0
        playerDuration = 0
        
        // 重置字幕
        currentSubtitleName = ""
        subtitleEntries = []

        playerLayer?.delegate = nil
        playerLayer?.pause()
        let url = APIService.videoStreamURL(name: item.relativePath)
        let layer = KSPlayerLayer(url: url, options: KSOptions(), delegate: playerDelegate)
        playerLayer = layer
        layer.play()
        isPlaying = true

        let name = item.name
        let bv = detectBVID(name)
        let tencentVid = detectTencentVID(name)
        let iqiyiId = detectIqiyiTVID(name)

        if let v = tencentVid, bv == nil {
            selectedSource = "qq"
            danmakuID = v
        } else if let v = bv {
            selectedSource = "bili"
            danmakuID = v
        } else if let v = iqiyiId {
            selectedSource = "iqiyi"
            danmakuID = v
        } else if let v = bv ?? tencentVid ?? iqiyiId {
            danmakuID = v
        } else {
            danmakuID = item.videoId ?? ""
        }

        if !danmakuID.isEmpty && !danmakuHidden {
            Task { await loadDanmaku() }
        }
        
        // 🚨 撤销了强行 Seek，把逻辑移到了 onStateChange 的 readyToPlay 中
    }

    private func deleteItem(at index: Int) {
        playlist.remove(at: index)
        if index == currentIndex && !playlist.isEmpty {
            playItem(at: min(index, playlist.count - 1))
        } else if playlist.isEmpty {
            currentIndex = -1
        } else if index < currentIndex {
            currentIndex -= 1
        }
    }

    private func loadDanmaku() async {
        guard !danmakuID.isEmpty else { return }
        do {
            let resp = try await APIService.shared.fetchDanmaku(source: selectedSource, id: danmakuID)
            engine.load(resp.danmus)
            statusMessage = "已加载 \(resp.count) 条弹幕"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    // MARK: - Subtitle Parsing & Actions

    private func fetchSubtitles() async {
        guard currentItem != nil else { return }
        isLoadingSubtitles = true
        showSubtitlePicker = true
        defer { isLoadingSubtitles = false }
        do {
            serverSubtitles = try await APIService.shared.fetchSubtitles()
        } catch {
            serverSubtitles = []
        }
    }

    // ✨ 修复：字幕获取与解析状态必须通过 MainActor 通知主线程 UI
    private func loadSubtitle(_ name: String) {
        currentSubtitleName = name
        Task {
            do {
                let url = APIService.videoStreamURL(name: name)
                let (data, _) = try await URLSession.shared.data(from: url)
                var parsed: [SubtitleEntry] = []
                
                let isASS = name.lowercased().hasSuffix(".ass") || name.lowercased().hasSuffix(".ssa")
                let encodings: [String.Encoding] = [
                    .utf8,
                    String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))),
                    .ascii,
                ]
                var text: String?
                for enc in encodings {
                    if let t = String(data: data, encoding: enc), !t.isEmpty {
                        text = t
                        break
                    }
                }
                if let text {
                    parsed = isASS ? parseASS(text) : parseSRT(text)
                }
                
                await MainActor.run {
                    self.subtitleEntries = parsed
                    self.statusMessage = "加载字幕: \(parsed.count) 条"
                    self.showSubtitlePicker = false
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = "字幕加载失败"
                    self.showSubtitlePicker = false
                }
            }
        }
    }

    private func parseSRT(_ content: String) -> [SubtitleEntry] {
        var entries: [SubtitleEntry] = []
        // Normalize line endings
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        for block in blocks {
            let lines = block.components(separatedBy: "\n").filter { !$0.isEmpty }
            guard lines.count >= 2 else { continue }
            // Find the time line (contains "-->")
            guard let timeIdx = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let timeLine = lines[timeIdx]
            let parts = timeLine.components(separatedBy: "-->").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 2 else { continue }
            let start = parseSRTTime(parts[0])
            let end = parseSRTTime(parts[1])
            let text = lines[(timeIdx + 1)...].joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\{[^}]*\}"#, with: "", options: .regularExpression)
            entries.append(SubtitleEntry(start: start, end: end, text: text))
        }
        return entries
    }

    private func parseSRTTime(_ s: String) -> Double {
        let cleaned = s.replacingOccurrences(of: ",", with: ".")
        let parts = cleaned.components(separatedBy: ":")
        guard parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]), let sec = Double(parts[2]) else { return 0 }
        return h * 3600 + m * 60 + sec
    }

    private func parseASS(_ content: String) -> [SubtitleEntry] {
        var entries: [SubtitleEntry] = []
        var inEvents = false
        let text = content.hasPrefix("\u{FEFF}") ? String(content.dropFirst()) : content
        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "[Events]" { inEvents = true; continue }
            if t.hasPrefix("[") && t != "[Events]" { inEvents = false; continue }
            guard inEvents, t.hasPrefix("Dialogue:") else { continue }
            guard let (start, end, text) = parseASSDialogue(t) else { continue }
            entries.append(SubtitleEntry(start: start, end: end, text: text))
        }
        return entries
    }

    private func parseASSDialogue(_ line: String) -> (Double, Double, String)? {
        let content = String(line.dropFirst("Dialogue:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        var remaining = content
        for _ in 0..<9 {
            if let idx = remaining.firstIndex(of: ",") {
                parts.append(String(remaining[..<idx]))
                remaining = String(remaining[remaining.index(after: idx)...])
            } else { break }
        }
        guard parts.count >= 2 else { return nil }
        let text = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\N", with: "\n").replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: #"\{[^}]*\}"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = parseASSTime(parts[1]), let end = parseASSTime(parts[2]) else { return nil }
        return (start, end, text)
    }

    private func parseASSTime(_ s: String) -> Double? {
        let parts = s.components(separatedBy: ":")
        guard parts.count == 3, let h = Double(parts[0]), let m = Double(parts[1]) else { return nil }
        let secParts = parts[2].components(separatedBy: ".")
        guard secParts.count == 2, let sec = Double(secParts[0]), let cs = Double(secParts[1]) else { return nil }
        return h * 3600 + m * 60 + sec + cs / 100.0
    }

    private func currentSubtitleText(at time: Double) -> String? {
        let matches = subtitleEntries.filter { time >= $0.start && time <= $0.end && !$0.text.isEmpty }
        if matches.isEmpty { return nil }
        return matches.map { $0.text }.joined(separator: "\n")
    }

    private var subtitlePickerSheet: some View {
        NavigationStack {
            List {
                if serverSubtitles.isEmpty {
                    Text("当前目录无字幕文件 (.srt .vtt .ass)")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(serverSubtitles, id: \.self) { sub in
                        Button {
                            loadSubtitle(sub)
                        } label: {
                            HStack {
                                Image(systemName: "doc.text.fill").foregroundColor(.orange)
                                Text(sub)
                                Spacer()
                                if currentSubtitleName == sub {
                                    Image(systemName: "checkmark").foregroundColor(.indigo)
                                }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
            }
            .navigationTitle("字幕")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showSubtitlePicker = false }
                }
            }
            .overlay { if isLoadingSubtitles { ProgressView() } }
        }
    }

    // MARK: - Time Observers (核心状态机与线程修复)

    // ✨ 修复：重新找回丢失的 MainActor 与 MKV 安全起播策略
    private func setupTimeObserver() {
        playerDelegate.onStateChange = { state in
            Task { @MainActor in
                switch state {
                case .paused, .error, .playedToTheEnd:
                    self.isPlaying = false
                case .readyToPlay, .bufferFinished:
                    self.isPlaying = true
                case .readyToPlay:
                    self.isPlaying = true
                    // 🚀 MKV 安全修复：就绪后再读取历史进度
                    if let item = self.currentItem {
                        let id = item.relativePath + "__" + String(item.name.hashValue)
                        Task {
                            if let p = try? await APIService.shared.fetchProgress(id: id), p.time > 0 {
                                await MainActor.run {
                                    self.playerLayer?.seek(time: p.time, autoPlay: true) { _ in }
                                }
                            }
                        }
                    }
                default:
                    break
                }
            }
        }
        
        playerDelegate.onTimeChange = { current, total in
            Task { @MainActor in
                let t = current
                if abs(t - self.lastCurrentTime) > 0.5 { self.engine.seek(to: t) }
                self.lastCurrentTime = t
                self.currentTime = t
                self.playerDuration = total
                if !self.isDraggingSlider { self.seekTarget = t }
            }
        }
        
        playerLayer?.delegate = playerDelegate

        videoEndedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                self.engine.reset()
                self.saveProgress()
                if self.autoplay, self.currentIndex + 1 < self.playlist.count {
                    self.playItem(at: self.currentIndex + 1)
                }
            }
        }

        progressSaveTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in self.saveProgress() }
        }
    }

    private func removeTimeObserver() {
        progressSaveTimer?.invalidate()
        if let obs = videoEndedObserver { NotificationCenter.default.removeObserver(obs) }
    }

    private func saveProgress() {
        guard let item = currentItem, currentTime > 0 else { return }
        let id = item.relativePath + "__" + String(item.name.hashValue)
        Task { try? await APIService.shared.saveProgress(id: id, time: currentTime) }
    }

    // Detect IDs...
    private func detectVideoID(_ name: String) -> String? {
        let base = name.replacingOccurrences(of: "\\.[^.]+$", with: "", options: .regularExpression)
        if let m = try? NSRegularExpression(pattern: "BV[0-9A-Za-z]+").firstMatch(in: base, range: NSRange(0..<base.count)),
           let r = Range(m.range, in: base) { return String(base[r]) }
        if let m = try? NSRegularExpression(pattern: "(?:^|[_-])(ep\\d{4,})(?:$|[_-])", options: .caseInsensitive).firstMatch(in: base, range: NSRange(0..<base.count)),
           let r = Range(m.range(at: 1), in: base) { return String(base[r]) }
        if let m = try? NSRegularExpression(pattern: "(?:^|[_-])([a-z][a-z0-9]{9,11})(?:$|[_.-])").firstMatch(in: base, range: NSRange(0..<base.count)),
           let r = Range(m.range(at: 1), in: base) { return String(base[r]) }
        if let m = try? NSRegularExpression(pattern: "(\\d{9,16})").firstMatch(in: base, range: NSRange(0..<base.count)),
           let r = Range(m.range(at: 1), in: base) { return String(base[r]) }
        return nil
    }

    private func detectBVID(_ name: String) -> String? {
        let base = name.replacingOccurrences(of: "\\.[^.]+$", with: "", options: .regularExpression)
        if let m = try? NSRegularExpression(pattern: "BV[0-9A-Za-z]+").firstMatch(in: base, range: NSRange(0..<base.count)),
           let r = Range(m.range, in: base) { return String(base[r]) }
        return nil
    }

    private func detectTencentVID(_ name: String) -> String? {
        let base = name.replacingOccurrences(of: "\\.[^.]+$", with: "", options: .regularExpression)
        if let m = try? NSRegularExpression(pattern: "(?:^|[_-])([a-z][a-z0-9]{9,11})(?:$|[_.-])").firstMatch(in: base, range: NSRange(0..<base.count)),
           let r = Range(m.range(at: 1), in: base) { return String(base[r]) }
        return nil
    }

    private func detectIqiyiTVID(_ name: String) -> String? {
        let base = name.replacingOccurrences(of: "\\.[^.]+$", with: "", options: .regularExpression)
        if let m = try? NSRegularExpression(pattern: "(\\d{9,16})").firstMatch(in: base, range: NSRange(0..<base.count)),
           let r = Range(m.range(at: 1), in: base) { return String(base[r]) }
        return nil
    }

    // MARK: - KSPlayerLayerDelegate (Fallback)

    func player(layer: KSPlayerLayer, state: KSPlayerState) {}
    func player(layer: KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {}
    func player(layer: KSPlayerLayer, finish error: Error?) {}
    func player(layer: KSPlayerLayer, bufferedCount: Int, consumeTime: TimeInterval) {}
}

// MARK: - Playlist Row

struct PlaylistRow: View {
    let item: VideoItem
    let isActive: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    private var cleanedDisplayName: String {
        var name = item.name
        let suffixesToRemove = [".mp4", ".mkv", ".mov", ".avi", "_4K", "_1080P", "_4k", "_1080p"]
        for suffix in suffixesToRemove {
            name = name.replacingOccurrences(of: suffix, with: "", options: .caseInsensitive)
        }
        return name
    }

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: APIService.fetchThumbnailURL(name: item.thumbnailName)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    Rectangle().fill(.quaternary)
                        .overlay(Image(systemName: "play.rectangle").font(.caption).foregroundStyle(.secondary))
                }
            }
            .frame(width: 88, height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(cleanedDisplayName)
                .font(.subheadline)
                .lineLimit(2)
                .foregroundColor(isActive ? .indigo : .primary)
                .bold(isActive)
            
            Spacer()
        }
        .padding(8)
        .background(isActive ? Color.indigo.opacity(0.08) : Color.primary.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("移除", systemImage: "trash")
            }
        }
    }
}

// MARK: - Player Delegate

final class PlayerDelegate: NSObject, KSPlayerLayerDelegate {
    var onStateChange: ((KSPlayerState) -> Void)?
    var onTimeChange: ((TimeInterval, TimeInterval) -> Void)?

    func player(layer: KSPlayerLayer, state: KSPlayerState) {
        onStateChange?(state)
    }

    func player(layer: KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {
        onTimeChange?(currentTime, totalTime)
    }

    func player(layer: KSPlayerLayer, finish error: Error?) {}

    func player(layer: KSPlayerLayer, bufferedCount: Int, consumeTime: TimeInterval) {}
}

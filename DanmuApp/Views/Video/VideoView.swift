import SwiftUI
import CoreMedia
import KSPlayer

struct VideoView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @StateObject private var engine = DanmakuEngine()
    @State private var playerLayer: KSPlayerLayer?
    @State private var showPlaylistSheet = false
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
    @AppStorage("subtitleMemory") private var subtitleMemoryData = "{}"
    @State private var currentSubtitleName = ""
    @State private var danmakuHidden = false
    @State private var isLoadingDanmaku = false
    @State private var subtitleEntries: [SubtitleEntry] = []

    // ✨ 动画控制状态变量
    @State private var syncTrigger = 0
    @State private var downloadTrigger = 0
    @State private var refreshTrigger = 0
    
    @State private var syncScale: CGFloat = 1.0
    @State private var downloadScale: CGFloat = 1.0
    @State private var refreshScale: CGFloat = 1.0

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
            let isCompact = sizeClass == .compact
            let sidebarWidth: CGFloat = 360

            HStack(spacing: 0) {
                playerArea(isLandscape: isLandscape)
                    .ignoresSafeArea(edges: isFullscreen ? .all : [])

                if isLandscape && showSidebar && !isFullscreen && !isCompact {
                    sidebarView
                        .frame(width: sidebarWidth)
                        .transition(.move(edge: .trailing))
                }
            }
            .ignoresSafeArea(edges: (isLandscape || isFullscreen) ? .bottom : [])
            .safeAreaPadding(.top, (isLandscape && !isFullscreen) ? 8 : 0)
            .overlay(alignment: .bottom) {
                if (!isLandscape || isCompact) && !isFullscreen { portraitControls }
            }
        }
        .onAppear {
            Task {
                // Check for library play target before loading folders
                let libFolder = UserDefaults.standard.string(forKey: "lib_play_folder")
                let libFile = UserDefaults.standard.string(forKey: "lib_play_file")
                if libFolder != nil {
                    UserDefaults.standard.removeObject(forKey: "lib_play_folder")
                    UserDefaults.standard.removeObject(forKey: "lib_play_file")
                }
                await loadFolders()
                setupTimeObserver()
                // Handle library play target after folders are loaded
                if let folder = libFolder, let file = libFile {
                    await switchFolder(folder)
                    if let idx = playlist.firstIndex(where: { $0.relativePath == file || $0.name == file }) {
                        playItem(at: idx)
                    }
                }
            }
        }
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
        .sheet(isPresented: $showPlaylistSheet) {
            NavigationStack {
                playlistList
                    .navigationTitle("播放列表")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("关闭") { showPlaylistSheet = false }
                        }
                    }
            }
        }
        .toolbar(isFullscreen ? .hidden : .visible, for: .tabBar)
    }

    // MARK: - Player Area

    private func playerArea(isLandscape: Bool) -> some View {
        ZStack {
            VideoPlayerView(playerLayer: $playerLayer)
            DanmakuOverlay(engine: engine, currentTime: currentTime, isPlaying: isPlaying)

            // 独立的全局字幕层
            if !currentSubtitleName.isEmpty, let text = currentSubtitleText(at: currentTime), !text.isEmpty {
                VStack {
                    Spacer()
                    Text(text)
                        .font(.system(size: isFullscreen ? 26 : 22, weight: .bold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.8), radius: 1, x: 1, y: 1)
                        .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 0)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.bottom, showControls ? 80 : 30)
                        .animation(.easeInOut(duration: 0.2), value: showControls)
                }
                .allowsHitTesting(false)
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
                                .shadow(radius: 2)
                        }
                    }
                    if isLandscape && !showSidebar && sizeClass != .compact {
                        Button {
                            withAnimation { showSidebar.toggle() }
                        } label: {
                            Image(systemName: "sidebar.left")
                                .font(.title3)
                                .padding(10)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .shadow(radius: 2)
                        }
                    }
                }
                .padding(12)
                .tint(.white)
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
                    Text(formatTime(currentTime)).font(.caption2).monospacedDigit().foregroundColor(.white)
                    Spacer()
                    Text(formatTime(playerDuration)).font(.caption2).monospacedDigit().foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .top)
            )
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
                    
                    // 全屏中央播放控制
                    HStack(spacing: 40) {
                        Button {
                            let t = max(0, currentTime - 15)
                            playerLayer?.seek(time: t, autoPlay: true) { _ in }
                        } label: {
                            Image(systemName: "gobackward.15")
                                .font(.system(size: 36))
                                .foregroundColor(.white.opacity(0.8))
                        }

                        Button {
                            isPlaying ? playerLayer?.pause() : playerLayer?.play()
                        } label: {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.white.opacity(0.8))
                        }

                        Button {
                            let t = min(playerDuration, currentTime + 15)
                            playerLayer?.seek(time: t, autoPlay: true) { _ in }
                        } label: {
                            Image(systemName: "goforward.15")
                                .font(.system(size: 36))
                                .foregroundColor(.white.opacity(0.8))
                        }
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
                // 正在播放区块
                if let current = currentItem {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "play.tv.fill")
                                    .font(.caption2)
                                Text("正在播放")
                                    .font(.caption2).bold()
                            }
                            .foregroundStyle(.indigo)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.indigo.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                            
                            Text(current.name.replacingOccurrences(of: "\\.[^.]+$", with: "", options: .regularExpression))
                                .font(.subheadline).bold()
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }

                // 控制按键面板
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Menu {
                            ForEach(sources, id: \.0) { src in
                                Button(src.1) { selectedSource = src.0 }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(sources.first(where: { $0.0 == selectedSource })?.1 ?? "B站")
                                Image(systemName: "chevron.up.chevron.down").font(.caption2)
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)

                        TextField("BV号 / ep / VID", text: $danmakuID)
                            .textFieldStyle(.roundedBorder)
                            .font(.subheadline)
                            .submitLabel(.search)
                            .onSubmit { Task { await triggerDownloadAction() } }
                            .frame(maxWidth: 130)

                        // ✨ 下载按钮（带组合动画）
                        Button {
                            Task { await triggerDownloadAction() }
                        } label: {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.title2)
                                .symbolEffect(.bounce, value: downloadTrigger) // 图标跳跃
                        }
                        .tint(.indigo)
                        .disabled(danmakuID.isEmpty || isLoadingDanmaku)
                        .scaleEffect(downloadScale) // 整体缩放

                        // ✨ 刷新按钮（带组合动画）
                        Button {
                            Task { await triggerRefreshAction() }
                        } label: {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .font(.title2)
                                .symbolEffect(.bounce, value: refreshTrigger) // 图标旋转跳跃
                        }
                        .tint(.orange)
                        .disabled(danmakuID.isEmpty || isLoadingDanmaku)
                        .scaleEffect(refreshScale) // 整体缩放
                        
                        Spacer()
                    }

                    // 播放与字幕工具栏
                    HStack(spacing: 12) {
                        Button {
                            isPlaying ? playerLayer?.pause() : playerLayer?.play()
                        } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.body)
                                .foregroundColor(isPlaying ? .orange : .indigo)
                                .frame(width: 20)
                        }
                        
                        // ✨ 同步按钮（横屏侧边栏，带组合动画）
                        Button {
                            triggerSyncAction()
                        } label: {
                            Label("同步", systemImage: "arrow.triangle.2.circlepath")
                                .symbolEffect(.bounce, value: syncTrigger) // 图标跳跃
                        }
                        .scaleEffect(syncScale) // 整体缩放
                        
                        Button { showSettings = true } label: {
                            Label("参数", systemImage: "slider.horizontal.3")
                        }

                        Button {
                            if currentSubtitleName.isEmpty {
                                Task { await loadSubtitleIfNeeded() }
                            } else {
                                clearSubtitle()
                            }
                        } label: {
                            Label("字幕", systemImage: currentSubtitleName.isEmpty ? "doc.text" : "doc.text.fill")
                                .foregroundColor(currentSubtitleName.isEmpty ? .primary : .green)
                        }
                        .disabled(isLoadingSubtitles)

                        Spacer()
                    }
                    .font(.footnote)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)

                Divider().padding(.horizontal, 16)

                playlistHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                playlistList
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showFolderPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.indigo)
                            Text(selectedFolderName)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .padding(.trailing, 8)
                    }
                    .buttonStyle(.plain)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation { showSidebar.toggle() }
                    } label: {
                        Image(systemName: "sidebar.right")
                            .foregroundColor(.indigo)
                            .fontWeight(.semibold)
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
            VStack(alignment: .leading, spacing: 12) {
                // 顶部：文件夹选择
                HStack {
                    Button {
                        showFolderPicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill").font(.subheadline).foregroundStyle(.indigo)
                            Text(selectedFolderName).font(.subheadline).bold().lineLimit(1)
                            Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                    
                    Spacer()
                    
                    Toggle("连播", isOn: $autoplay)
                        .toggleStyle(.switch)
                        .scaleEffect(0.8)
                        .frame(width: 80)
                }

                // 弹幕区
                HStack(spacing: 8) {
                    Picker("弹幕源", selection: $selectedSource) {
                        ForEach(sources, id: \.0) { src in Text(src.1).tag(src.0) }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    TextField("BV号/VID", text: $danmakuID)
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                        .frame(maxWidth: 130)

                    // ✨ 竖屏下载按钮（带组合动画）
                    Button {
                        Task { await triggerDownloadAction() }
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title3)
                            .symbolEffect(.bounce, value: downloadTrigger)
                    }
                    .tint(.indigo)
                    .disabled(danmakuID.isEmpty || isLoadingDanmaku)
                    .scaleEffect(downloadScale)
                    
                    // ✨ 竖屏刷新按钮（带组合动画）
                    Button {
                        Task { await triggerRefreshAction() }
                    } label: {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.title3)
                            .symbolEffect(.bounce, value: refreshTrigger)
                    }
                    .tint(.orange)
                    .disabled(danmakuID.isEmpty || isLoadingDanmaku)
                    .scaleEffect(refreshScale)
                    
                    Spacer()
                }

                // 工具和控制按键行
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button { isPlaying ? playerLayer?.pause() : playerLayer?.play() } label: {
                            Label(isPlaying ? "暂停" : "播放", systemImage: isPlaying ? "pause.fill" : "play.fill").font(.subheadline)
                        }
                        .buttonStyle(.borderedProminent).tint(isPlaying ? .orange : .indigo)
                        
                        Button { showSettings = true } label: {
                            Label("设置", systemImage: "slider.horizontal.3").font(.subheadline)
                        }.buttonStyle(.bordered)
                        
                        // ✨ 同步按钮（竖屏工具栏，带组合动画）
                        Button {
                            triggerSyncAction()
                        } label: {
                            Label("同步", systemImage: "arrow.triangle.2.circlepath")
                                .font(.subheadline)
                                .symbolEffect(.bounce, value: syncTrigger)
                        }
                        .buttonStyle(.bordered)
                        .scaleEffect(syncScale)
                        
                        Button {
                            if currentSubtitleName.isEmpty {
                                Task { await loadSubtitleIfNeeded() }
                            } else {
                                clearSubtitle()
                            }
                        } label: {
                            Label("字幕", systemImage: currentSubtitleName.isEmpty ? "doc.text" : "doc.text.fill").font(.subheadline)
                                .foregroundColor(currentSubtitleName.isEmpty ? .primary : .green)
                        }.buttonStyle(.bordered).disabled(isLoadingSubtitles)

                        Button { withAnimation { isFullscreen = true } } label: {
                            Label("全屏", systemImage: "arrow.up.left.and.arrow.down.right").font(.subheadline)
                        }.buttonStyle(.bordered)

                        if sizeClass == .compact {
                            Button { showPlaylistSheet = true } label: {
                                Label("列表", systemImage: "list.bullet").font(.subheadline)
                            }.buttonStyle(.bordered)
                        }
                    }
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage).font(.caption2).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .background(.regularMaterial)

            if !playlist.isEmpty {
                playlistList
                    .frame(maxHeight: 220)
                    .background(Color(uiColor: .systemGroupedBackground))
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }

    // MARK: - Animation Trigger Helpers

    private func triggerSyncAction() {
        // 1. 改变触发计数值以便系统图标捕获 bounce 效果
        syncTrigger += 1
        // 2. 先瞬间微小压缩，再弹性恢复正常大小
        syncScale = 0.88
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
            syncScale = 1.0
        }
        // 3. 执行业务逻辑
        engine.seek(to: currentTime)
    }

    private func triggerDownloadAction() async {
        guard !danmakuID.isEmpty else { return }
        downloadTrigger += 1
        downloadScale = 0.88
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
            downloadScale = 1.0
        }
        await loadDanmaku()
    }

    private func triggerRefreshAction() async {
        guard !danmakuID.isEmpty else { return }
        refreshTrigger += 1
        refreshScale = 0.88
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
            refreshScale = 1.0
        }
        await refreshDanmaku()
    }

    // MARK: - Folder Picker & Lists

    private var folderPickerSheet: some View {
        NavigationStack {
            List {
                ForEach(folders) { f in
                    Button {
                        Task {
                            isLoadingVideos = true
                            selectedFolder = f.path
                            await switchFolder(f.path)
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
            .listStyle(.insetGrouped)
            .navigationTitle("选择视频库")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if isLoadingVideos {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView("正在加载视频列表...")
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
            Text("播放列表").font(.headline).foregroundColor(.primary)
            Spacer()
            Text("\(playlist.count) 个视频")
                .font(.caption).bold()
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.secondary.opacity(0.15))
                .clipShape(Capsule())
        }
    }

    private var playlistList: some View {
        Group {
            if playlist.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray").font(.title2).foregroundStyle(.secondary)
                    Text("选择目录加载视频").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
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
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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
            let savedIndex = loadPlayIndex(folder: dir) ?? 0
            let startIndex = savedIndex < playlist.count ? savedIndex : 0
            statusMessage = "已加载 \(playlist.count) 个视频"
            if !playlist.isEmpty { playItem(at: startIndex) }
            let mem = (try? JSONDecoder().decode([String: String].self, from: Data(subtitleMemoryData.utf8))) ?? [:]
            if let saved = mem[dir], !saved.isEmpty {
                loadSubtitle(saved)
            } else {
                // 只有一个字幕时自动加载
                let subs = (try? await APIService.shared.fetchSubtitles()) ?? []
                if subs.count == 1 { loadSubtitle(subs[0]) }
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func playItem(at index: Int) {
        guard index < playlist.count else { return }
        if let old = currentItem, currentTime > 0 {
            saveProgress(item: old, time: currentTime)
        }
        // Remember this index for the current folder
        savePlayIndex(folder: selectedFolder, index: index)
        engine.reset()
        currentIndex = index
        let item = playlist[index]
        lastCurrentTime = 0
        currentTime = 0
        seekTarget = 0
        playerDuration = 0
        
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
        isLoadingDanmaku = true
        statusMessage = "正在加载 \(danmakuID) 弹幕..."
        do {
            let strategy = selectedSource == "bili" ? "seg.so" : ""
            let resp = try await APIService.shared.fetchDanmaku(source: selectedSource, id: danmakuID, strategy: strategy)
            engine.load(resp.danmus)
            statusMessage = "已加载 \(resp.count) 条弹幕"
        } catch {
            statusMessage = error.localizedDescription
        }
        isLoadingDanmaku = false
    }

    private func refreshDanmaku() async {
        guard !danmakuID.isEmpty else { return }
        isLoadingDanmaku = true
        statusMessage = "正在刷新 \(danmakuID) 弹幕..."
        do {
            let strategy = selectedSource == "bili" ? "seg.so" : ""
            let resp = try await APIService.shared.fetchDanmaku(source: selectedSource, id: danmakuID, strategy: strategy, refresh: true)
            engine.load(resp.danmus)
            statusMessage = "已刷新 \(resp.count) 条弹幕"
        } catch {
            statusMessage = error.localizedDescription
        }
        isLoadingDanmaku = false
    }

    // MARK: - Subtitle Parsing & Actions

    private func loadSubtitleIfNeeded() async {
        guard currentItem != nil else { return }
        isLoadingSubtitles = true
        defer { isLoadingSubtitles = false }
        do {
            let subs = try await APIService.shared.fetchSubtitles()
            serverSubtitles = subs
            if subs.count == 1 {
                loadSubtitle(subs[0])
            } else {
                showSubtitlePicker = true
            }
        } catch {
            serverSubtitles = []
        }
    }

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

    private func savePlayIndex(folder: String, index: Int) {
        let key = "playIndexMemory"
        var mem = [String: Int]()
        if let data = UserDefaults.standard.data(forKey: key) {
            mem = (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
        }
        mem[folder] = index
        if let data = try? JSONEncoder().encode(mem) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func loadPlayIndex(folder: String) -> Int? {
        let key = "playIndexMemory"
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return (try? JSONDecoder().decode([String: Int].self, from: data))?[folder]
    }

    private func saveSubtitleMemory(folder: String) {
        var mem = (try? JSONDecoder().decode([String: String].self, from: Data(subtitleMemoryData.utf8))) ?? [:]
        mem[folder] = currentSubtitleName
        if let data = try? JSONEncoder().encode(mem), let str = String(data: data, encoding: .utf8) {
            subtitleMemoryData = str
        }
    }

    private func clearSubtitle() {
        currentSubtitleName = ""
        subtitleEntries = []
        saveSubtitleMemory(folder: selectedFolder)
    }

    private func loadSubtitle(_ name: String) {
        currentSubtitleName = name
        saveSubtitleMemory(folder: selectedFolder)
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
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        for block in blocks {
            let lines = block.components(separatedBy: "\n").filter { !$0.isEmpty }
            guard lines.count >= 2 else { continue }
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
            .listStyle(.insetGrouped)
            .navigationTitle("选择字幕")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showSubtitlePicker = false }
                }
            }
            .overlay { if isLoadingSubtitles { ProgressView() } }
        }
    }

    // MARK: - Time Observers

    private func setupTimeObserver() {
        playerDelegate.onStateChange = { state in
            Task { @MainActor in
                switch state {
                case .paused, .error, .playedToTheEnd:
                    self.isPlaying = false
                case .readyToPlay:
                    self.isPlaying = true
                    if let item = self.currentItem {
                        let id = item.relativePath
                        Task {
                            if let p = try? await APIService.shared.fetchProgress(id: id), p.time > 0 {
                                await MainActor.run {
                                    self.playerLayer?.seek(time: p.time, autoPlay: true) { _ in }
                                }
                            }
                        }
                    }
                case .bufferFinished:
                    self.isPlaying = true
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

    private func saveProgress(item: VideoItem, time: Double) {
        guard time > 0 else { return }
        Task { try? await APIService.shared.saveProgress(id: item.relativePath, time: time) }
    }

    private func saveProgress() {
        guard let item = currentItem, currentTime > 0 else { return }
        saveProgress(item: item, time: currentTime)
    }

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
        HStack(spacing: 14) {
            AsyncImage(url: APIService.fetchThumbnailURL(name: item.thumbnailName)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                default:
                    Rectangle().fill(.quaternary)
                        .overlay(Image(systemName: "play.tv.fill").font(.title3).foregroundStyle(.tertiary))
                }
            }
            .frame(width: 100, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(cleanedDisplayName)
                .font(.subheadline)
                .lineLimit(2)
                .foregroundColor(isActive ? .indigo : .primary)
                .fontWeight(isActive ? .bold : .regular)
            
            Spacer()
            
            if isActive {
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundColor(.indigo)
            }
        }
        .padding(8)
        .background(isActive ? Color.indigo.opacity(0.1) : Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

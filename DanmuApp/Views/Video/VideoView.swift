import SwiftUI
import AVKit

struct VideoView: View {
    @StateObject private var engine = DanmakuEngine()
    @State private var player = AVPlayer()
    @State private var currentTime: Double = 0.0
    @State private var playerDuration: Double = 0.0
    @State private var isPlaying: Bool = false
    @State private var seekTarget: Double = 0
    @State private var isDraggingSlider: Bool = false
    @State private var showControls: Bool = true
    @State private var controlsTimer: Task<Void, Never>?
    @State private var isFullscreen: Bool = false
    @State private var timeObserver: Any?
    @State private var durationObserver: NSKeyValueObservation?
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

    private let sources = [
        ("bili", "B站"), ("qq", "腾讯"), ("mango", "芒果"), ("iqiyi", "爱奇艺")
    ]

    var body: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            let sidebarWidth: CGFloat = 360

            HStack(spacing: 0) {
                playerArea(isLandscape: isLandscape)
                if isLandscape && showSidebar {
                    sidebarView
                        .frame(width: sidebarWidth)
                        .transition(.move(edge: .trailing))
                }
            }
            .ignoresSafeArea(edges: isLandscape ? .bottom : [])
            .safeAreaPadding(.top, isLandscape ? 8 : 0)
            .overlay(alignment: .bottom) {
                if !isLandscape { portraitControls }
            }
        }
        .onAppear { Task { await loadFolders(); setupTimeObserver() } }
        .onDisappear { player.pause(); isPlaying = false; saveProgress(); removeTimeObserver(); controlsTimer?.cancel() }
        .sheet(isPresented: $showSettings) {
            DanmakuSettings(config: $engine.config)
        }
        .sheet(isPresented: $showFolderPicker) {
            folderPickerSheet
                .onAppear { Task { await loadFolders() } }
        }
        .fullScreenCover(isPresented: $isFullscreen) {
            FullscreenPlayerView(
                player: player,
                engine: engine,
                currentTime: currentTime,
                playerDuration: playerDuration,
                isPlaying: $isPlaying,
                seekTarget: $seekTarget,
                isDraggingSlider: $isDraggingSlider,
                isFullscreen: $isFullscreen
            )
        }
    }

    // MARK: - Player Area

    private func playerArea(isLandscape: Bool) -> some View {
        ZStack {
            VideoPlayerView(player: .constant(player))
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
                                .background(.indigo, in: RoundedRectangle(cornerRadius: 8))
                                .transition(.opacity.combined(with: .scale(scale: 1.1)))
                        }
                        Slider(
                            value: $seekTarget,
                            in: 0...max(playerDuration, 1),
                            onEditingChanged: { editing in
                                isDraggingSlider = editing
                                if !editing {
                                    Task { await player.seek(to: CMTime(seconds: seekTarget, preferredTimescale: 600)) }
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
                    .background(.ultraThinMaterial.opacity(0.6))
                    .transition(.opacity)
                }
                .transition(.opacity)
            }
        }
        .background(.black)
        .animation(.easeInOut(duration: 0.3), value: showControls)
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 8) {
                if showControls || (isLandscape && showSidebar) {
                    Button { isFullscreen = true } label: {
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
        .onTapGesture {
            if isPlaying { player.pause() } else { player.play() }
            showControls = true
            resetControlsTimer()
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
                // 1. 顶部当前媒体看板 (利用原有的空白区域展示正在播放)
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

                // 2. 弹幕载入与配置面板 (融合菜单，极大瘦身)
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

                    // 快捷控制流
                    HStack(spacing: 12) {
                        Button {
                            isPlaying ? player.pause() : player.play()
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

                        Spacer()

                        if !statusMessage.isEmpty {
                            Text(statusMessage)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .font(.footnote)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                // 3. 播放列表头部
                playlistHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                // 4. 无缝丝滑滚动列表 (去掉过时分页)
                playlistList
            }
            .background(.ultraThinMaterial)
            // 原生导航栏注入，将切换目录等按钮规范置顶
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
                    Button { isPlaying ? player.pause() : player.play() } label: {
                        Label(isPlaying ? "暂停" : "播放", systemImage: isPlaying ? "pause.fill" : "play.fill").font(.caption)
                    }
                    .buttonStyle(.borderedProminent).tint(isPlaying ? .orange : .indigo)
                    Button { showSettings = true } label: {
                        Label("设置", systemImage: "slider.horizontal.3").font(.caption)
                    }.buttonStyle(.bordered)
                    Button { engine.seek(to: currentTime) } label: {
                        Label("同步", systemImage: "arrow.triangle.2.circlepath").font(.caption)
                    }.buttonStyle(.bordered)
                    Button { isFullscreen = true } label: {
                        Label("全屏", systemImage: "arrow.up.left.and.arrow.down.right").font(.caption)
                    }.buttonStyle(.bordered)
                    Spacer()

                    Toggle("连播", isOn: $autoplay).toggleStyle(.switch)
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            if !playlist.isEmpty {
                playlistList.frame(maxHeight: 180)
            }
        }
        .background(.regularMaterial)
    }

    // MARK: - Folder Picker Sheet

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

    // MARK: - Playlist Components

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

        player.pause()
        player.automaticallyWaitsToMinimizeStalling = true
        let url = APIService.shared.videoStreamURL(name: item.relativePath)
        let playerItem = AVPlayerItem(url: url)
        playerItem.preferredForwardBufferDuration = 30
        player.replaceCurrentItem(with: playerItem)
        player.play()
        isPlaying = true

        durationObserver?.invalidate()
        durationObserver = playerItem.observe(\.duration, options: [.new]) { item, _ in
            let d = item.duration.seconds
            if d.isFinite, d > 0 {
                Task { @MainActor in playerDuration = d }
            }
        }

        let vid = detectVideoID(item.name)
        danmakuID = vid ?? ""
        if vid != nil, !danmakuID.isEmpty {
            Task { await autoLoadDanmaku(id: danmakuID) }
        }

        Task {
            let id = item.relativePath + "__" + String(item.name.hashValue)
            if let p = try? await APIService.shared.fetchProgress(id: id) {
                let time = CMTime(seconds: p.time, preferredTimescale: 600)
                await player.seek(to: time)
            }
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
        do {
            let resp = try await APIService.shared.fetchDanmaku(source: selectedSource, id: danmakuID)
            engine.load(resp.danmus)
            statusMessage = "已加载 \(resp.count) 条弹幕"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func autoLoadDanmaku(id: String) async {
        do {
            let resp = try await APIService.shared.fetchDanmaku(source: selectedSource, id: id)
            engine.load(resp.danmus)
        } catch {}
    }

    private func saveProgress() {
        guard let item = currentItem, currentTime > 0 else { return }
        let id = item.relativePath + "__" + String(item.name.hashValue)
        Task { try? await APIService.shared.saveProgress(id: id, time: currentTime) }
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
        if let obs = timeObserver { player.removeTimeObserver(obs) }
        durationObserver?.invalidate()
        progressSaveTimer?.invalidate()
        if let obs = videoEndedObserver { NotificationCenter.default.removeObserver(obs) }
    }
}

// MARK: - Playlist Row (Modernized Style)

struct PlaylistRow: View {
    let item: VideoItem
    let isActive: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    // 后缀清洗逻辑：移除文件名中的多余脏数据
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
            // 标准 16:9 比例缩略图
            AsyncImage(url: APIService.shared.fetchThumbnailURL(name: item.thumbnailName)) { phase in
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

// MARK: - Fullscreen Player

struct FullscreenPlayerView: View {
    let player: AVPlayer
    @ObservedObject var engine: DanmakuEngine
    let currentTime: Double
    let playerDuration: Double
    @Binding var isPlaying: Bool
    @Binding var seekTarget: Double
    @Binding var isDraggingSlider: Bool
    @Binding var isFullscreen: Bool

    @State private var showControls: Bool = true
    @State private var controlsTimer: Task<Void, Never>?

    var body: some View {
        ZStack {
            VideoPlayerView(player: .constant(player))
            DanmakuOverlay(engine: engine, currentTime: currentTime, isPlaying: isPlaying)

            VStack {
                HStack {
                    Spacer()
                    Button {
                        isFullscreen = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
            }
            .opacity(showControls ? 1 : 0)

            if showControls {
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
                                    Task { await player.seek(to: CMTime(seconds: seekTarget, preferredTimescale: 600)) }
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
                    .background(.ultraThinMaterial.opacity(0.6))
                }
                .transition(.opacity)
            }
        }
        .background(.black)
        .animation(.easeInOut(duration: 0.3), value: showControls)
        .ignoresSafeArea()
        .statusBarHidden()
        .onTapGesture {
            if isPlaying { player.pause() } else { player.play() }
            showControls = true
            resetControlsTimer()
        }
        .onAppear { resetControlsTimer() }
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
}

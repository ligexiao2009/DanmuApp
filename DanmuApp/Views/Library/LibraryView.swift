import SwiftUI

struct LibraryView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var items: [LibraryItem] = []
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var searchText = ""
    @State private var refreshID = UUID()

    var onPlayEpisode: ((_ folderPath: String, _ videoFile: String) -> Void)?

    private var isCompact: Bool { sizeClass == .compact }
    private var gridColumns: Int { isCompact ? 3 : 4 }

    private var filteredItems: [LibraryItem] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { item in
            item.title.lowercased().contains(q) ||
            (item.year ?? "").contains(q) ||
            (item.genres ?? []).contains(where: { $0.lowercased().contains(q) })
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().padding()
                } else if filteredItems.isEmpty && !items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").font(.system(size: 48)).foregroundColor(.secondary)
                        Text("未找到匹配的剧集").font(.callout).foregroundColor(.secondary)
                    }
                } else if items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tv").font(.system(size: 48)).foregroundColor(.secondary)
                        Text("没有找到剧集库").font(.callout).foregroundColor(.secondary)
                        Button("刷新") { Task { await load() } }.buttonStyle(.borderedProminent).controlSize(.small)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: gridColumns), spacing: 16) {
                            ForEach(filteredItems) { item in
                                NavigationLink {
                                    LibraryDetailView(item: item, onPlayEpisode: onPlayEpisode)
                                } label: {
                                    LibraryCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .id(refreshID)
                        .padding(14)
                    }
                }
            }
            .navigationTitle("")
            .searchable(text: $searchText, prompt: "搜索片名、年份、类型...")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await load() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isRefreshing)
                }
            }
            .refreshable { await load() }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = items.isEmpty
        isRefreshing = true
        do { items = try await APIService.shared.fetchLibraryItems() } catch { /* keep existing items on error */ }
        refreshID = UUID()
        isLoading = false
        isRefreshing = false
    }
}

// MARK: - Detail View

struct LibraryDetailView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let item: LibraryItem
    var onPlayEpisode: ((_ folderPath: String, _ videoFile: String) -> Void)?

    @State private var detail: LibraryDetail?
    @State private var isLoading = true
    @State private var errorMsg: String?
    @State private var lastWatchedEp: Int?

    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载详情...").padding()
            } else if let detail {
                let localFiles = detail.localFiles ?? []
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header: poster left + info right (stacks on phone)
                        let posterSize: (w: CGFloat, h: CGFloat) = isCompact ? (100, 140) : (140, 196)
                        let layout = isCompact ? AnyLayout(VStackLayout(alignment: .center, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                        layout {
                            if let poster = detail.poster ?? item.poster {
                                AsyncImage(url: APIService.shared.libraryPosterURL(originalURL: poster)) { phase in
                                    switch phase {
                                    case .success(let img): img.resizable().scaledToFill()
                                    default: Color.gray.opacity(0.2)
                                    }
                                }
                                .frame(width: posterSize.w, height: posterSize.h)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Text(detail.title).font(.title2.bold())
                                HStack(spacing: 12) {
                                    if let year = detail.year { Text(year).font(.subheadline).foregroundColor(.secondary) }
                                    if let ds = detail.doubanScore { Label("豆瓣 \(ds)", systemImage: "star.fill").font(.subheadline).foregroundColor(.green) }
                                    if let ep = detail.episodeAll { Text("共 \(ep) 集").font(.subheadline).foregroundColor(.secondary) }
                                }
                                if let desc = detail.description, !desc.isEmpty {
                                    Text(desc).font(.subheadline).foregroundColor(.secondary).lineLimit(6)
                                }
                            }
                        }

                        Divider()

                        // Cast
                        if let cast = detail.cast, !cast.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("演员").font(.headline)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(cast, id: \.name) { p in
                                            VStack(spacing: 4) {
                                                if let avatar = p.avatar {
                                                    AsyncImage(url: APIService.shared.libraryPosterURL(originalURL: avatar)) { phase in
                                                        switch phase {
                                                        case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                                                        default: Color.gray.opacity(0.2)
                                                        }
                                                    }
                                                    .frame(width: 60, height: 60).clipShape(Circle())
                                                }
                                                Text(p.name).font(.caption2).lineLimit(1)
                                                if let role = p.role { Text(role).font(.caption2).foregroundColor(.secondary).lineLimit(1) }
                                            }.frame(width: 70)
                                        }
                                    }
                                }
                            }
                        }

                        // Episodes Grid — pad to episodeAll if needed
                        let totalEpisodes = detail.episodeAll ?? detail.episodes?.count ?? 0
                        let episodes = detail.episodes ?? []
                        let paddedEpisodes = episodes + (episodes.count < totalEpisodes ? Array(repeating: Episode(), count: totalEpisodes - episodes.count) : [])
                        if !paddedEpisodes.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("分集").font(.headline)
                                // Build episode number set from filenames (same logic as web)
                                let localSet: Set<Int> = {
                                    var s = Set<Int>()
                                    for fn in localFiles {
                                        let base = (fn as NSString).deletingPathExtension
                                        // Match S01E20, S02E05 etc.
                                        if let r = try? NSRegularExpression(pattern: #"S\d+E(\d+)"#, options: [.caseInsensitive]).firstMatch(in: base, range: NSRange(0..<base.utf16.count)) {
                                            if r.numberOfRanges > 1, let nr = Range(r.range(at: 1), in: base) {
                                                if let n = Int(base[nr]), n > 0 { s.insert(n) }
                                            }
                                        } else if let r = try? NSRegularExpression(pattern: #"(?:^|[_\s-])EP?(\d{2,3})(?=[_\s-]|$|\.)"#, options: [.caseInsensitive]).firstMatch(in: base, range: NSRange(0..<base.utf16.count)) {
                                            if r.numberOfRanges > 1, let nr = Range(r.range(at: 1), in: base) {
                                                if let n = Int(base[nr]), n > 0 { s.insert(n) }
                                            }
                                        } else if let r = try? NSRegularExpression(pattern: #"(?:^|[_\s])(\d{1,2})(?=[_\s\-]|$|\.)"#, options: []).firstMatch(in: base, range: NSRange(0..<base.utf16.count)) {
                                            if r.numberOfRanges > 1, let nr = Range(r.range(at: 1), in: base) {
                                                if let n = Int(base[nr]), n > 0 { s.insert(n) }
                                            }
                                        }
                                    }
                                    return s
                                }()
                                // Last watched episode from playIndexMemory (computed on appear)
                                let hasPosters = episodes.contains(where: { $0.poster?.isEmpty == false })
                                let columns = hasPosters ? 4 : 10
                                let chunked = stride(from: 0, to: episodes.count, by: columns).map {
                                    Array(episodes[$0..<min($0+columns, episodes.count)])
                                }
                                ForEach(Array(chunked.enumerated()), id: \.offset) { chunkIdx, row in
                                    HStack(spacing: 6) {
                                        ForEach(Array(row.enumerated()), id: \.offset) { idx, ep in
                                            let globalIdx = chunkIdx * columns + idx
                                            let epNum = (ep.episode ?? 0) > 0 ? ep.episode! : (globalIdx + 1)
                                            let hasFile = localSet.isEmpty || localSet.contains(epNum)
                                            Button {
                                                guard hasFile else { return }
                                                let file = matchedFile(for: epNum, in: localFiles)
                                                onPlayEpisode?(item.folderPath, file)
                                            } label: {
                                                if hasPosters {
                                                    let isLast = hasFile && epNum == lastWatchedEp
                                                    VStack(spacing: 4) {
                                                        if isLast {
                                                            Text("上次").font(.system(size: 9, weight: .bold))
                                                                .foregroundColor(.white)
                                                                .padding(.horizontal, 6).padding(.vertical, 1)
                                                                .background(Color.blue).clipShape(Capsule())
                                                        }
                                                        if let poster = ep.poster {
                                                            AsyncImage(url: APIService.shared.libraryPosterURL(originalURL: poster)) { p in
                                                                switch p {
                                                                case .success(let img): img.resizable().scaledToFill()
                                                                default: Color.gray.opacity(0.2)
                                                                }
                                                            }
                                                            .frame(height: 130).clipped()
                                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                                        } else {
                                                            Rectangle().fill(.quaternary).frame(height: 130)
                                                        }
                                                        Text(ep.title ?? "第\(epNum)集").font(.caption2).lineLimit(1)
                                                            .foregroundColor(hasFile ? .green : .secondary)
                                                    }
                                                    .padding(6)
                                                    .background(isLast ? Color.blue.opacity(0.08) : (hasFile ? Color.green.opacity(0.08) : Color.gray.opacity(0.05)))
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .stroke(isLast ? Color.blue : Color.clear, lineWidth: 2)
                                                    )
                                                } else {
                                                    let isLast = hasFile && epNum == lastWatchedEp
                                                    Text("\(epNum)").font(.body.bold())
                                                        .foregroundColor(isLast ? .blue : (hasFile ? .green : .secondary))
                                                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                                                        .background(isLast ? Color.blue.opacity(0.1) : (hasFile ? Color.green.opacity(0.1) : Color.gray.opacity(0.05)))
                                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: 8)
                                                                .stroke(isLast ? Color.blue : Color.clear, lineWidth: 2)
                                                        )
                                                }
                                            }
                                            .buttonStyle(.plain).disabled(!hasFile)
                                        }
                                        if row.count < columns {
                                            ForEach(0..<(columns - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                                        }
                                    }
                                }
                            }

                            // Local files list
                            if !localFiles.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("文件列表").font(.headline)
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 4) {
                                        ForEach(localFiles, id: \.self) { fn in
                                            Button { onPlayEpisode?(item.folderPath, fn) } label: {
                                                VStack(spacing: 2) {
                                                    Image(systemName: "play.rectangle.fill").font(.title3).foregroundColor(.green)
                                                    Text(fn).font(.caption2).lineLimit(2).multilineTextAlignment(.center).foregroundColor(.secondary)
                                                }
                                                .padding(6)
                                                .frame(maxWidth: .infinity)
                                                .background(Color.green.opacity(0.05))
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundColor(.orange)
                    Text(errorMsg ?? "加载失败").foregroundColor(.secondary)
                    Button("重试") { Task { await loadDetail() } }.buttonStyle(.borderedProminent).controlSize(.small)
                }.padding()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { Task { await loadDetail(refresh: true) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task { await loadDetail() }
        .onAppear { computeLastWatchedEp() }
    }

    private func computeLastWatchedEp() {
        guard let files = detail?.localFiles, !files.isEmpty else { lastWatchedEp = nil; return }
        let key = "playIndexMemory"
        guard let data = UserDefaults.standard.data(forKey: key),
              let mem = try? JSONDecoder().decode([String: Int].self, from: data),
              let idx = mem[item.folderPath],
              idx < files.count else { lastWatchedEp = nil; return }
        let fn = files[idx]
        let base = (fn as NSString).deletingPathExtension
        let r0 = try? NSRegularExpression(pattern: #"S\d+E(\d+)"#, options: [.caseInsensitive]).firstMatch(in: base, range: NSRange(0..<base.utf16.count))
        if let r0, r0.numberOfRanges > 1, let nr = Range(r0.range(at: 1), in: base), let n = Int(base[nr]), n > 0 { lastWatchedEp = n; return }
        let r1 = try? NSRegularExpression(pattern: #"(?:^|[_\s-])EP?(\d{2,3})(?=[_\s-]|$|\.)"#, options: [.caseInsensitive]).firstMatch(in: base, range: NSRange(0..<base.utf16.count))
        if let r1, r1.numberOfRanges > 1, let nr = Range(r1.range(at: 1), in: base), let n = Int(base[nr]), n > 0 { lastWatchedEp = n; return }
        let r2 = try? NSRegularExpression(pattern: #"(?:^|[_\s])(\d{1,2})(?=[_\s\-]|$|\.)"#, options: []).firstMatch(in: base, range: NSRange(0..<base.utf16.count))
        if let r2, r2.numberOfRanges > 1, let nr = Range(r2.range(at: 1), in: base), let n = Int(base[nr]), n > 0 { lastWatchedEp = n; return }
        lastWatchedEp = idx + 1
    }

    private func loadDetail(refresh: Bool = false) async {
        isLoading = true
        errorMsg = nil
        do {
            detail = try await APIService.shared.fetchLibraryInfo(folderPath: item.folderPath, refresh: refresh)
        } catch {
            errorMsg = error.localizedDescription
        }
        isLoading = false
        computeLastWatchedEp()
    }

    private func matchedFile(for epNum: Int, in files: [String]) -> String {
        // Try regex-based matching first
        if let match = files.first(where: { fn in
            let base = (fn as NSString).deletingPathExtension
            let r0 = try? NSRegularExpression(pattern: #"S\d+E(\d+)"#, options: [.caseInsensitive]).firstMatch(in: base, range: NSRange(0..<base.utf16.count))
            if let r0, r0.numberOfRanges > 1, let nr = Range(r0.range(at: 1), in: base) { return Int(base[nr]) == epNum }
            let r1 = try? NSRegularExpression(pattern: #"(?:^|[_\s-])EP?(\d{2,3})(?=[_\s-]|$|\.)"#, options: [.caseInsensitive]).firstMatch(in: base, range: NSRange(0..<base.utf16.count))
            if let r1, r1.numberOfRanges > 1, let nr = Range(r1.range(at: 1), in: base) { return Int(base[nr]) == epNum }
            let r2 = try? NSRegularExpression(pattern: #"(?:^|[_\s])(\d{1,2})(?=[_\s\-]|$|\.)"#, options: []).firstMatch(in: base, range: NSRange(0..<base.utf16.count))
            if let r2, r2.numberOfRanges > 1, let nr = Range(r2.range(at: 1), in: base) { return Int(base[nr]) == epNum }
            return false
        }) {
            return match
        }
        // Fallback: index-based matching for files without episode numbers (e.g. B站)
        let idx = epNum - 1
        if idx >= 0 && idx < files.count { return files[idx] }
        return files.first ?? ""
    }

    private func formatDuration(_ sec: Int) -> String {
        let m = sec / 60
        let h = m / 60
        if h > 0 { return "\(h)时\(m % 60)分" }
        return "\(m)分\(sec % 60)秒"
    }
}

// MARK: - Card

struct LibraryCard: View {
    let item: LibraryItem

    var body: some View {
        VStack(spacing: 6) {
            if let poster = item.poster {
                Color.clear.aspectRatio(200.0/280.0, contentMode: .fit)
                    .overlay {
                        AsyncImage(url: APIService.shared.libraryPosterURL(originalURL: poster)) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFill()
                            default: EmptyView()
                            }
                        }
                        .allowsHitTesting(false)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            VStack(spacing: 2) {
                Text(item.title).font(.subheadline.bold()).lineLimit(2).multilineTextAlignment(.center)
            if !(item.score ?? "").isEmpty || item.year != nil || !(item.genres ?? []).isEmpty {
                HStack(spacing: 4) {
                    if let s = item.score.flatMap({ Double($0) }), s > 0 {
                        Text(String(format: "★%.1f", s)).font(.caption.bold()).foregroundColor(.orange)
                    }
                    if let y = item.year, !y.isEmpty { Text(y).font(.caption).foregroundColor(.secondary) }
                    ForEach((item.genres ?? []).prefix(2), id: \.self) { g in
                        Text(g).font(.caption2).padding(.horizontal, 4).padding(.vertical, 1)
                            .background(.quaternary).clipShape(Capsule())
                    }
                }
            }
            if let epAll = item.episodeAll, epAll > 1 {
                Text("\(epAll)集").font(.caption2).foregroundColor(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 4))
            } else if item.episodeAll == 1 {
                Text("电影").font(.caption2).foregroundColor(.blue)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.blue.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 4))
            }
            }
        }
        .padding(8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

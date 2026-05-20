import SwiftUI

struct LibraryView: View {
    @State private var items: [LibraryItem] = []
    @State private var isLoading = false

    var onPlayEpisode: ((_ folderPath: String, _ videoFile: String) -> Void)?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().padding()
                } else if items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tv").font(.system(size: 48)).foregroundColor(.secondary)
                        Text("没有找到剧集库").font(.callout).foregroundColor(.secondary)
                        Button("刷新") { Task { await load() } }.buttonStyle(.borderedProminent).controlSize(.small)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 16) {
                            ForEach(items) { item in
                                NavigationLink {
                                    LibraryDetailView(item: item, onPlayEpisode: onPlayEpisode)
                                } label: {
                                    LibraryCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(14)
                    }
                }
            }
            .navigationTitle("剧集库")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        do { items = try await APIService.shared.fetchLibraryItems() } catch { items = [] }
        isLoading = false
    }
}

// MARK: - Detail View

struct LibraryDetailView: View {
    let item: LibraryItem
    var onPlayEpisode: ((_ folderPath: String, _ videoFile: String) -> Void)?

    @State private var detail: LibraryDetail?
    @State private var isLoading = true
    @State private var errorMsg: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("加载详情...").padding()
            } else if let detail {
                let localFiles = detail.localFiles ?? []
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header: poster left + info right
                        HStack(alignment: .top, spacing: 16) {
                            if let poster = detail.poster ?? item.poster {
                                AsyncImage(url: APIService.shared.libraryPosterURL(originalURL: poster)) { phase in
                                    switch phase {
                                    case .success(let img): img.resizable().scaledToFill()
                                    default: Color.gray.opacity(0.2)
                                    }
                                }
                                .frame(width: 140, height: 196)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Text(detail.title).font(.title2.bold())
                                HStack(spacing: 12) {
                                    if let year = detail.year { Text(year).font(.subheadline).foregroundColor(.secondary) }
                                    if let s = detail.score { Label(s, systemImage: "star.fill").font(.subheadline).foregroundColor(.orange) }
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
                                        // Match E01, EP01, EP02 etc.
                                        if let r = try? NSRegularExpression(pattern: #"EP?(\d{2,3})"#, options: [.caseInsensitive]).firstMatch(in: base, range: NSRange(0..<base.utf16.count)) {
                                            if r.numberOfRanges > 1, let nr = Range(r.range(at: 1), in: base) {
                                                if let n = Int(base[nr]), n > 0 { s.insert(n) }
                                            }
                                        } else if let r = try? NSRegularExpression(pattern: #"(?:^|[_\s])(\d{1,2})(?=[_\s]|$|\.)"#, options: []).firstMatch(in: base, range: NSRange(0..<base.utf16.count)) {
                                            if r.numberOfRanges > 1, let nr = Range(r.range(at: 1), in: base) {
                                                if let n = Int(base[nr]), n > 0 { s.insert(n) }
                                            }
                                        }
                                    }
                                    return s
                                }()
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
                                                let file = hasPosters ? (localFiles.first ?? "") : matchedFile(for: epNum, in: localFiles)
                                                onPlayEpisode?(item.folderPath, file)
                                            } label: {
                                                if hasPosters {
                                                    VStack(spacing: 4) {
                                                        if let poster = ep.poster {
                                                            AsyncImage(url: APIService.shared.libraryPosterURL(originalURL: poster)) { p in
                                                                switch p {
                                                                case .success(let img): img.resizable().scaledToFill()
                                                                default: Color.gray.opacity(0.2)
                                                                }
                                                            }
                                                            .frame(height: 100).clipped()
                                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                                        } else {
                                                            Rectangle().fill(.quaternary).frame(height: 100)
                                                        }
                                                        Text(ep.title ?? "第\(epNum)集").font(.caption2).lineLimit(1)
                                                            .foregroundColor(hasFile ? .green : .secondary)
                                                    }
                                                    .padding(6)
                                                    .background(hasFile ? Color.green.opacity(0.08) : Color.gray.opacity(0.05))
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                                } else {
                                                    Text("\(epNum)").font(.body.bold())
                                                        .foregroundColor(hasFile ? .green : .secondary)
                                                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                                                        .background(hasFile ? Color.green.opacity(0.1) : Color.gray.opacity(0.05))
                                                        .clipShape(RoundedRectangle(cornerRadius: 8))
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
    }

    private func matchedFile(for epNum: Int, in files: [String]) -> String {
        files.first(where: { fn in
            let base = (fn as NSString).deletingPathExtension
            let r1 = try? NSRegularExpression(pattern: #"EP?(\d{2,3})"#, options: [.caseInsensitive]).firstMatch(in: base, range: NSRange(0..<base.utf16.count))
            if let r1, r1.numberOfRanges > 1, let nr = Range(r1.range(at: 1), in: base) { return Int(base[nr]) == epNum }
            let r2 = try? NSRegularExpression(pattern: #"(?:^|[_\s])(\d{1,2})(?=[_\s]|$|\.)"#, options: []).firstMatch(in: base, range: NSRange(0..<base.utf16.count))
            if let r2, r2.numberOfRanges > 1, let nr = Range(r2.range(at: 1), in: base) { return Int(base[nr]) == epNum }
            return false
        }) ?? files.first ?? ""
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
                    if let s = item.score, !s.isEmpty {
                        Text("★\(s)").font(.caption.bold()).foregroundColor(.orange)
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
            }
            }
        }
        .padding(8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

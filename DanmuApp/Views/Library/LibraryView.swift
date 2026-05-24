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
      item.title.lowercased().contains(q) || (item.year ?? "").contains(q)
        || (item.genres ?? []).contains(where: { $0.lowercased().contains(q) })
    }
  }

  var body: some View {
    NavigationStack {
      Group {
        if isLoading {
          ProgressView("加载剧集中...")
            .padding()
        } else if filteredItems.isEmpty && !items.isEmpty {
          VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
              .font(.system(size: 56))
              .foregroundStyle(.tertiary)
            Text("未找到匹配的剧集")
              .font(.title3.bold())
              .foregroundColor(.secondary)
          }
        } else if items.isEmpty {
          VStack(spacing: 16) {
            Image(systemName: "tv.slash")
              .font(.system(size: 56))
              .foregroundStyle(.tertiary)
            Text("剧库为空")
              .font(.title3.bold())
              .foregroundColor(.secondary)
            Button("刷新") {
              Task { await load() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
          }
        } else {
          ScrollView {
            LazyVGrid(
              columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: gridColumns),
              spacing: 20
            ) {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
          }
        }
      }
      .navigationTitle("剧库")
      .navigationBarTitleDisplayMode(.inline)
      .searchable(text: $searchText, prompt: "搜索片名、年份、类型...")
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button {
            Task { await load() }
          } label: {
            Image(systemName: "arrow.clockwise")
              .fontWeight(.medium)
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
    do { items = try await APIService.shared.fetchLibraryItems() } catch
    { /* keep existing items on error */  }
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
        ProgressView("加载详情...")
          .padding()
      } else if let detail {
        let localFiles = detail.localFiles ?? []
        ScrollView {
          VStack(alignment: .leading, spacing: 28) {
            // Header
            let posterSize: (w: CGFloat, h: CGFloat) = isCompact ? (110, 160) : (160, 230)
            let layout =
              isCompact
              ? AnyLayout(VStackLayout(alignment: .center, spacing: 16))
              : AnyLayout(HStackLayout(alignment: .top, spacing: 20))

            layout {
              if let poster = detail.poster ?? item.poster {
                CachedPosterView(url: APIService.shared.libraryPosterURL(originalURL: poster), fallbackIcon: "photo")
                .frame(width: posterSize.w, height: posterSize.h)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
              }

              VStack(alignment: isCompact ? .center : .leading, spacing: 10) {
                Text(detail.title)
                  .font(.title.weight(.bold))
                  .multilineTextAlignment(isCompact ? .center : .leading)

                HStack(spacing: 8) {
                  if let year = detail.year {
                    Text(year).font(.subheadline.bold())
                      .padding(.horizontal, 8).padding(.vertical, 4)
                      .background(Color(uiColor: .tertiarySystemGroupedBackground))
                      .clipShape(Capsule())
                  }
                  if let ds = detail.doubanScore {
                    Label(ds, systemImage: "star.fill")
                      .font(.subheadline.bold())
                      .foregroundColor(.orange)
                      .padding(.horizontal, 8).padding(.vertical, 4)
                      .background(Color.orange.opacity(0.1))
                      .clipShape(Capsule())
                  }
                  if let ep = detail.episodeAll {
                    Text("共 \(ep) 集")
                      .font(.subheadline)
                      .padding(.horizontal, 8).padding(.vertical, 4)
                      .background(Color(uiColor: .tertiarySystemGroupedBackground))
                      .clipShape(Capsule())
                  }
                }

                if let desc = detail.description, !desc.isEmpty {
                  Text(desc)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(isCompact ? 4 : 6)
                    .lineSpacing(4)
                    .multilineTextAlignment(isCompact ? .center : .leading)
                    .padding(.top, 4)
                }
              }
            }

            Divider()

            // Cast
            if let cast = detail.cast, !cast.isEmpty {
              VStack(alignment: .leading, spacing: 12) {
                Text("演职员")
                  .font(.title3.bold())

                ScrollView(.horizontal, showsIndicators: false) {
                  HStack(spacing: 16) {
                    ForEach(cast, id: \.name) { p in
                      VStack(spacing: 6) {
                        if let avatar = p.avatar {
                          CachedPosterView(url: APIService.shared.libraryPosterURL(originalURL: avatar), fallbackIcon: "person.fill")
                          .frame(width: 64, height: 64)
                          .clipShape(Circle())
                          .overlay(Circle().stroke(Color.primary.opacity(0.1), lineWidth: 1))
                        }
                        Text(p.name)
                          .font(.caption.weight(.medium))
                          .lineLimit(1)
                        if let role = p.role {
                          Text(role)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        }
                      }
                      .frame(width: 72)
                    }
                  }
                  .padding(.horizontal, 2)
                }
              }
            }

            // Episodes Grid
            let totalEpisodes = detail.episodeAll ?? detail.episodes?.count ?? 0
            let episodes = detail.episodes ?? []
            let paddedEpisodes =
              episodes
              + (episodes.count < totalEpisodes
                ? Array(repeating: Episode(), count: totalEpisodes - episodes.count) : [])

            if !paddedEpisodes.isEmpty {
              VStack(alignment: .leading, spacing: 12) {
                Text("分集")
                  .font(.title3.bold())

                let localSet: Set<Int> = {
                  var s = Set<Int>()
                  for fn in localFiles {
                    let base = (fn as NSString).deletingPathExtension
                    if let r = try? NSRegularExpression(
                      pattern: #"S\d+E(\d+)"#, options: [.caseInsensitive]
                    ).firstMatch(in: base, range: NSRange(0..<base.utf16.count)) {
                      if r.numberOfRanges > 1, let nr = Range(r.range(at: 1), in: base),
                        let n = Int(base[nr]), n > 0
                      {
                        s.insert(n)
                      }
                    } else if let r = try? NSRegularExpression(
                      pattern: #"(?:^|[_\s-])EP?(\d{2,3})(?=[_\s-]|$|\.)"#,
                      options: [.caseInsensitive]
                    ).firstMatch(in: base, range: NSRange(0..<base.utf16.count)) {
                      if r.numberOfRanges > 1, let nr = Range(r.range(at: 1), in: base),
                        let n = Int(base[nr]), n > 0
                      {
                        s.insert(n)
                      }
                    } else if let r = try? NSRegularExpression(
                      pattern: #"(?:^|[_\s])(\d{1,2})(?=[_\s\-]|$|\.)"#, options: []
                    ).firstMatch(in: base, range: NSRange(0..<base.utf16.count)) {
                      if r.numberOfRanges > 1, let nr = Range(r.range(at: 1), in: base),
                        let n = Int(base[nr]), n > 0
                      {
                        s.insert(n)
                      }
                    }
                  }
                  return s
                }()

                let hasPosters = episodes.contains(where: { $0.poster?.isEmpty == false })
                let columns = hasPosters ? 4 : (isCompact ? 6 : 10)
                let chunked = stride(from: 0, to: episodes.count, by: columns).map {
                  Array(episodes[$0..<min($0 + columns, episodes.count)])
                }

                ForEach(Array(chunked.enumerated()), id: \.offset) { chunkIdx, row in
                  HStack(spacing: 8) {
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
                          VStack(spacing: 6) {
                            ZStack(alignment: .topTrailing) {
                              if let poster = ep.poster {
                                CachedPosterView(url: APIService.shared.libraryPosterURL(originalURL: poster))
                                .frame(height: 120).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                              } else {
                                RoundedRectangle(cornerRadius: 8)
                                  .fill(Color(uiColor: .secondarySystemBackground))
                                  .frame(height: 120)
                              }

                              if isLast {
                                Text("上次播放")
                                  .font(.system(size: 9, weight: .bold))
                                  .foregroundColor(.white)
                                  .padding(.horizontal, 6).padding(.vertical, 3)
                                  .background(Color.accentColor)
                                  .clipShape(Capsule())
                                  .padding(4)
                              }
                            }

                            Text(ep.title ?? "第\(epNum)集")
                              .font(.caption.weight(.medium))
                              .lineLimit(1)
                              .foregroundColor(
                                isLast ? .accentColor : (hasFile ? .primary : .secondary))
                          }
                          .opacity(hasFile ? 1.0 : 0.5)
                        } else {
                          let isLast = hasFile && epNum == lastWatchedEp
                          Text("\(epNum)")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundColor(isLast ? .white : (hasFile ? .primary : .secondary))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                              isLast
                                ? Color.accentColor
                                : (hasFile
                                  ? Color(uiColor: .secondarySystemBackground)
                                  : Color(uiColor: .tertiarySystemBackground))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                      }
                      .buttonStyle(.plain)
                      .disabled(!hasFile)
                    }
                    if row.count < columns {
                      ForEach(0..<(columns - row.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                      }
                    }
                  }
                }
              }

              // Local files list
              if !localFiles.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                  Text("本地文件")
                    .font(.title3.bold())

                  LazyVStack(spacing: 8) {
                    ForEach(localFiles, id: \.self) { fn in
                      Button {
                        onPlayEpisode?(item.folderPath, fn)
                      } label: {
                        HStack(spacing: 12) {
                          Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundColor(.accentColor)

                          Text(fn)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                          Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                      }
                      .buttonStyle(.plain)
                    }
                  }
                }
                .padding(.top, 8)
              }
            }
          }
          .padding(20)
        }
      } else {
        VStack(spacing: 16) {
          Image(systemName: "exclamationmark.triangle")
            .font(.system(size: 56))
            .foregroundColor(.orange)
          Text(errorMsg ?? "加载失败")
            .font(.body)
            .foregroundColor(.secondary)
          Button("重试") {
            Task { await loadDetail() }
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.regular)
        }
        .padding()
      }
    }
    .navigationTitle("")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button {
          Task { await loadDetail(refresh: true) }
        } label: {
          Image(systemName: "arrow.clockwise")
            .fontWeight(.medium)
        }
      }
    }
    .task { await loadDetail() }
    .onAppear { computeLastWatchedEp() }
  }

  private func computeLastWatchedEp() {
    guard let files = detail?.localFiles, !files.isEmpty else {
      lastWatchedEp = nil
      return
    }
    let key = "playIndexMemory"
    guard let data = UserDefaults.standard.data(forKey: key),
      let mem = try? JSONDecoder().decode([String: Int].self, from: data),
      let idx = mem[item.folderPath],
      idx < files.count
    else {
      lastWatchedEp = nil
      return
    }
    let fn = files[idx]
    let base = (fn as NSString).deletingPathExtension
    let r0 = try? NSRegularExpression(pattern: #"S\d+E(\d+)"#, options: [.caseInsensitive])
      .firstMatch(in: base, range: NSRange(0..<base.utf16.count))
    if let r0, r0.numberOfRanges > 1, let nr = Range(r0.range(at: 1), in: base),
      let n = Int(base[nr]), n > 0
    {
      lastWatchedEp = n
      return
    }
    let r1 = try? NSRegularExpression(
      pattern: #"(?:^|[_\s-])EP?(\d{2,3})(?=[_\s-]|$|\.)"#, options: [.caseInsensitive]
    ).firstMatch(in: base, range: NSRange(0..<base.utf16.count))
    if let r1, r1.numberOfRanges > 1, let nr = Range(r1.range(at: 1), in: base),
      let n = Int(base[nr]), n > 0
    {
      lastWatchedEp = n
      return
    }
    let r2 = try? NSRegularExpression(
      pattern: #"(?:^|[_\s])(\d{1,2})(?=[_\s\-]|$|\.)"#, options: []
    ).firstMatch(in: base, range: NSRange(0..<base.utf16.count))
    if let r2, r2.numberOfRanges > 1, let nr = Range(r2.range(at: 1), in: base),
      let n = Int(base[nr]), n > 0
    {
      lastWatchedEp = n
      return
    }
    lastWatchedEp = idx + 1
  }

  private func loadDetail(refresh: Bool = false) async {
    isLoading = true
    errorMsg = nil
    do {
      detail = try await APIService.shared.fetchLibraryInfo(
        folderPath: item.folderPath, refresh: refresh)
    } catch {
      errorMsg = error.localizedDescription
    }
    isLoading = false
    computeLastWatchedEp()
  }

  private func matchedFile(for epNum: Int, in files: [String]) -> String {
    if let match = files.first(where: { fn in
      let base = (fn as NSString).deletingPathExtension
      let r0 = try? NSRegularExpression(pattern: #"S\d+E(\d+)"#, options: [.caseInsensitive])
        .firstMatch(in: base, range: NSRange(0..<base.utf16.count))
      if let r0, r0.numberOfRanges > 1, let nr = Range(r0.range(at: 1), in: base) {
        return Int(base[nr]) == epNum
      }
      let r1 = try? NSRegularExpression(
        pattern: #"(?:^|[_\s-])EP?(\d{2,3})(?=[_\s-]|$|\.)"#, options: [.caseInsensitive]
      ).firstMatch(in: base, range: NSRange(0..<base.utf16.count))
      if let r1, r1.numberOfRanges > 1, let nr = Range(r1.range(at: 1), in: base) {
        return Int(base[nr]) == epNum
      }
      let r2 = try? NSRegularExpression(
        pattern: #"(?:^|[_\s])(\d{1,2})(?=[_\s\-]|$|\.)"#, options: []
      ).firstMatch(in: base, range: NSRange(0..<base.utf16.count))
      if let r2, r2.numberOfRanges > 1, let nr = Range(r2.range(at: 1), in: base) {
        return Int(base[nr]) == epNum
      }
      return false
    }) {
      return match
    }
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
    VStack(alignment: .leading, spacing: 0) {
      // Poster Area
      Color.clear.aspectRatio(2.0 / 3.0, contentMode: .fit)
        .overlay {
          if let poster = item.poster {
            CachedPosterView(url: APIService.shared.libraryPosterURL(originalURL: poster))
          } else {
            Color(uiColor: .secondarySystemBackground)
              .overlay(Image(systemName: "film").foregroundStyle(.tertiary))
          }
        }
        .clipped()

      // Info Area
      VStack(alignment: .leading, spacing: 6) {
        Text(item.title)
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
          .foregroundColor(.primary)

        HStack(spacing: 6) {
          if let s = item.score.flatMap({ Double($0) }), s > 0 {
            Text(String(format: "★ %.1f", s))
              .font(.caption.weight(.bold))
              .foregroundColor(.orange)
          }
          if let y = item.year, !y.isEmpty {
            Text(y)
              .font(.caption2)
              .foregroundColor(.secondary)
          }
          Spacer(minLength: 0)
        }

        HStack(spacing: 4) {
          if let epAll = item.episodeAll, epAll > 1 {
            Text("\(epAll)集")
              .font(.system(size: 10, weight: .medium))
              .foregroundColor(.secondary)
              .padding(.horizontal, 6).padding(.vertical, 2)
              .background(Color(uiColor: .tertiarySystemGroupedBackground))
              .clipShape(Capsule())
          } else if item.episodeAll == 1 {
            Text("电影")
              .font(.system(size: 10, weight: .medium))
              .foregroundColor(.accentColor)
              .padding(.horizontal, 6).padding(.vertical, 2)
              .background(Color.accentColor.opacity(0.1))
              .clipShape(Capsule())
          }

          if let genres = item.genres, !genres.isEmpty {
            ForEach(genres.prefix(1), id: \.self) { g in
              Text(g)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                .clipShape(Capsule())
            }
          }
        }
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(uiColor: .secondarySystemGroupedBackground))
    }
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
  }
}

// MARK: - Cached Poster Image

struct CachedPosterView: View {
  let url: URL?
  var fallbackIcon: String = "film"
  @State private var image: Image?
  @State private var loadState: LoadState = .loading

  enum LoadState { case loading, loaded, failed }

  var body: some View {
    Group {
      switch loadState {
      case .loaded:
        if let image { image.resizable().scaledToFill() }
      case .loading:
        ProgressView()
      case .failed:
        Color(uiColor: .secondarySystemBackground)
          .overlay(Image(systemName: fallbackIcon).foregroundStyle(.tertiary))
      }
    }
    .task(id: url) { await load() }
  }

  private func load() async {
    guard let url else { loadState = .failed; return }
    let request = URLRequest(url: url)
    if let cached = URLCache.shared.cachedResponse(for: request),
       let img = UIImage(data: cached.data) {
      image = Image(uiImage: img)
      loadState = .loaded
      return
    }
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      URLCache.shared.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
      if let img = UIImage(data: data) {
        image = Image(uiImage: img)
        loadState = .loaded
      } else {
        loadState = .failed
      }
    } catch {
      loadState = .failed
    }
  }
}

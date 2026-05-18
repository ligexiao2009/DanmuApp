import SwiftUI

struct HomeView: View {
    @Binding var selectedTab: ContentView.Tab
    @State private var recentItems: [RecentItem] = []
    @State private var serverStatus: ServerStatus = .checking

    enum ServerStatus { case checking, connected, disconnected }

    struct RecentItem: Identifiable {
        let id: String
        let name: String
        let progress: Double
        let duration: Double
        var progressPercent: Double { duration > 0 ? min(progress / duration * 100, 100) : 0 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                headerSection
                entryCardsSection
                if !recentItems.isEmpty { recentSection }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 40)
        }
        .background(Color(.systemGroupedBackground))
        .task { await checkServer() }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("弹幕播放器")
                .font(.largeTitle.bold())
            Text("B站 · 腾讯 · 芒果 · 爱奇艺 · 直播吧")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Entry Cards

    private var entryCardsSection: some View {
        HStack(spacing: 20) {
            Button {
                selectedTab = .live
            } label: {
                EntryCard(
                    title: "直播",
                    subtitle: "M3U8 / HLS",
                    icon: "antenna.radiowaves.left.and.right",
                    color: .red
                )
            }
            .buttonStyle(.plain)

            Button {
                selectedTab = .video
            } label: {
                EntryCard(
                    title: "视频",
                    subtitle: "本地/服务器视频",
                    icon: "play.rectangle",
                    color: .indigo
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近播放")
                .font(.title2.bold())
            ForEach(recentItems) { item in
                RecentRow(item: item)
            }
        }
    }

    // MARK: - Server Status

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(serverStatus == .connected ? Color.green : serverStatus == .checking ? Color.orange : Color.red)
                .frame(width: 8, height: 8)
            Text(statusLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private var statusLabel: String {
        switch serverStatus {
        case .checking: return "检测中..."
        case .connected: return "服务器已连接"
        case .disconnected: return "服务器断开"
        }
    }

    private func checkServer() async {
        do {
            _ = try await APIService.shared.fetchFolders()
            serverStatus = .connected
        } catch {
            serverStatus = .disconnected
        }
    }
}

// MARK: - Subviews

struct EntryCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(color)
                .frame(height: 60)
            VStack(spacing: 4) {
                Text(title).font(.title3.bold())
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Text("进入 →").font(.caption.bold())
                .foregroundColor(color)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(color.opacity(0.1))
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct RecentRow: View {
    let item: HomeView.RecentItem

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .frame(width: 80, height: 45)
                .overlay(Text("🎬").font(.title3))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.callout).lineLimit(1)
                ProgressView(value: item.progressPercent, total: 100)
                    .tint(.indigo)
                    .scaleEffect(x: 1, y: 0.8)
            }
        }
        .padding(10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

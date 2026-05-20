import Foundation

struct VideoItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let relativePath: String
    let videoId: String?
    let thumbnailName: String
    let isRemote: Bool

    var displayName: String {
        name.removingPercentEncoding ?? name
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: VideoItem, rhs: VideoItem) -> Bool { lhs.id == rhs.id }
}

struct FolderItem: Identifiable, Decodable {
    let path: String
    let name: String

    var id: String { path }
}

struct PlaybackProgress: Decodable {
    let time: Double
}

struct StreamSniffResult: Decodable {
    let streamUrl: String
    let method: String?
}

struct TxspSniffResult: Decodable {
    let roomId: String
    let programId: String
    let cookie: String?
}

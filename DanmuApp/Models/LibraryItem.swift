import Foundation

struct LibraryItem: Decodable, Identifiable, Hashable {
    var id: String { folderPath }
    func hash(into hasher: inout Hasher) { hasher.combine(folderPath) }
    static func == (lhs: LibraryItem, rhs: LibraryItem) -> Bool { lhs.folderPath == rhs.folderPath }
    let folderName: String
    let folderPath: String
    let videoFile: String?
    let title: String
    let poster: String?
    let year: String?
    let score: String?
    let episodeAll: Int?
    let source: String?
    let hasCache: Bool?
    let genres: [String]?
}

struct LibraryDetail: Decodable {
    let title: String
    let poster: String?
    let year: String?
    let area: String?
    let genres: [String]?
    let plotTags: String?
    let episodeAll: Int?
    let score: String?
    let doubanScore: String?
    let description: String?
    let directors: [Person]?
    let cast: [CastMember]?
    let episodes: [Episode]?
    let localFiles: [String]?
    let source: String?
}

struct Person: Decodable {
    let name: String
}

struct CastMember: Decodable {
    let name: String
    let role: String?
    let avatar: String?
}

struct Episode: Decodable, Identifiable {
    var id: Int { episode ?? title.flatMap { Int($0) } ?? 0 }
    let episode: Int?
    let title: String?
    let duration: Int?
    let poster: String?

    init(episode: Int? = nil, title: String? = nil, duration: Int? = nil, poster: String? = nil) {
        self.episode = episode
        self.title = title
        self.duration = duration
        self.poster = poster
    }

    init(from decoder: Decoder) {
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        episode = (try? c?.decodeIfPresent(Int.self, forKey: .episode)) ?? nil
        title = (try? c?.decodeIfPresent(String.self, forKey: .title)) ?? nil
        poster = (try? c?.decodeIfPresent(String.self, forKey: .poster)) ?? nil
        if let d = try? c?.decodeIfPresent(Int.self, forKey: .duration) {
            duration = d
        } else {
            duration = nil
        }
    }

    enum CodingKeys: CodingKey { case episode, title, duration, poster }
}

struct LibraryPlayResult: Decodable {
    let file: String?
    let episode: Int?
}

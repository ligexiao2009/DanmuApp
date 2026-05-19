import Foundation

struct DanmakuItem: Identifiable, Decodable {
    let id = UUID()
    let time: Double
    let text: String
    let color: String?
    let ctime: Double?

    enum CodingKeys: String, CodingKey {
        case time, text, color, ctime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        time = try c.decode(Double.self, forKey: .time)
        text = try c.decode(String.self, forKey: .text)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        // ctime can be String or Double from different sources
        if let s = try? c.decodeIfPresent(String.self, forKey: .ctime) {
            ctime = Double(s)
        } else {
            ctime = try c.decodeIfPresent(Double.self, forKey: .ctime)
        }
    }

    init(time: Double, text: String, color: String? = nil) {
        self.time = time
        self.text = text
        self.color = color
        self.ctime = nil
    }
}

struct DanmakuResponse: Decodable {
    let danmus: [DanmakuItem]
    let count: Int
    let fromCache: Bool?
    let maxId: Int?
    let maxSeq: Int?
    let cursor: String?
    let pullInterval: Int?

    enum CodingKeys: String, CodingKey {
        case danmus, count, cursor
        case fromCache = "from_cache"
        case maxId = "maxId"
        case maxSeq = "maxSeq"
        case pullInterval = "pullInterval"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        danmus = try c.decode([DanmakuItem].self, forKey: .danmus)
        count = try c.decode(Int.self, forKey: .count)
        fromCache = try c.decodeIfPresent(Bool.self, forKey: .fromCache)
        maxId = try c.decodeIfPresent(Int.self, forKey: .maxId)
        maxSeq = try c.decodeIfPresent(Int.self, forKey: .maxSeq)
        cursor = try c.decodeIfPresent(String.self, forKey: .cursor)
        pullInterval = try c.decodeIfPresent(Int.self, forKey: .pullInterval)
    }
}

struct APIResponse<T: Decodable>: Decodable {
    let code: Int
    let data: T?
    let message: String
}

struct DanmakuConfig: Codable {
    var speed: Double = 18
    var area: Int = 25
    var offset: Double = 0
    var fontSize: Double = 24
    var opacity: Double = 1.0

    private static let udKey = "danmakuConfig"

    static func load() -> DanmakuConfig {
        guard let data = UserDefaults.standard.data(forKey: udKey),
              let cfg = try? JSONDecoder().decode(Self.self, from: data)
        else { return DanmakuConfig() }
        return cfg
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.udKey)
        }
    }
}

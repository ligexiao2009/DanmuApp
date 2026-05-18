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
        ctime = try c.decodeIfPresent(Double.self, forKey: .ctime)
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

    enum CodingKeys: String, CodingKey {
        case danmus, count
        case fromCache = "from_cache"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        danmus = try c.decode([DanmakuItem].self, forKey: .danmus)
        count = try c.decode(Int.self, forKey: .count)
        fromCache = try c.decodeIfPresent(Bool.self, forKey: .fromCache)
    }
}

struct APIResponse<T: Decodable>: Decodable {
    let code: Int
    let data: T?
    let message: String
}

struct DanmakuConfig {
    var speed: Double = 18
    var area: Int = 25
    var offset: Double = 0
    var fontSize: Double = 24
    var opacity: Double = 1.0
}

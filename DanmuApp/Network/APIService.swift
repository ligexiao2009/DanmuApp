import Foundation

actor APIService {
    static let shared = APIService()
    private static let baseURL = "http://YangdeMacBook-Air.local:5001"
    private let decoder: JSONDecoder
    private let session: URLSession

    init() {
        decoder = JSONDecoder()
        session = URLSession(configuration: .default)
    }

    static func fetchThumbnailURL(name: String) -> URL {
        URL(string: "\(Self.baseURL)/api/thumbnail?name=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name)")!
    }

    static func videoStreamURL(name: String) -> URL {
        URL(string: "\(Self.baseURL)/stream?name=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name)")!
    }

    // MARK: - Danmaku

    func fetchDanmaku(source: String, id: String, strategy: String = "seg.so", duration: Int? = nil, refresh: Bool = false) async throws -> DanmakuResponse {
        var params = ["source": source, "id": id, "strategy": strategy]
        if let d = duration { params["duration"] = String(d) }
        if refresh { params["refresh"] = "1" }
        return try await get("/api/danmaku", params: params)
    }

    func fetchZhibo8Danmaku(matchId: String, type: String, lastMaxId: Int) async throws -> DanmakuResponse {
        return try await get("/api/danmaku", params: [
            "source": "zhibo8", "id": matchId, "type": type,
            "lastMaxId": String(lastMaxId)
        ])
    }

    func fetchTxspDanmaku(roomId: String, programId: String, lastSeq: Int, cursor: String) async throws -> DanmakuResponse {
        return try await get("/api/danmaku", params: [
            "source": "txsp", "roomId": roomId, "programId": programId,
            "lastSeq": String(lastSeq), "cursor": cursor
        ])
    }

    // MARK: - Videos

    func fetchVideos() async throws -> [String] {
        return try await get("/api/videos")
    }

    func fetchFolders() async throws -> [FolderItem] {
        return try await get("/api/folders")
    }

    // MARK: - Progress

    func fetchProgress(id: String) async throws -> PlaybackProgress {
        return try await get("/api/progress", params: ["id": id])
    }

    func saveProgress(id: String, time: Double) async throws {
        try await postIgnoreResponse("/api/progress", body: ["id": id, "time": time])
    }

    // MARK: - Sniff

    func sniffStream(pageUrl: String) async throws -> StreamSniffResult {
        return try await post("/api/stream/sniff", body: ["pageUrl": pageUrl])
    }

    // MARK: - Config

    func setVideoDir(_ dir: String) async throws {
        try await putIgnoreResponse("/api/config", body: ["videoDir": dir])
    }

    func fetchFolderHistory() async throws -> [String: String] {
        return try await get("/api/folder-history")
    }

    func saveFolderHistory(dir: String, name: String) async throws {
        try await putIgnoreResponse("/api/folder-history", body: ["dir": dir, "name": name])
    }

    // MARK: - HTTP core

    private func makeURL(_ path: String, params: [String: String] = [:]) -> URL {
        var components = URLComponents(string: "\(Self.baseURL)\(path)")!
        if !params.isEmpty {
            components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url!
    }

    /// Extract code + data from a JSON response, then decode data as T
    private func decodeData<T: Decodable>(_ raw: Data) throws -> T {
        let json = try JSONSerialization.jsonObject(with: raw) as? [String: Any]
        guard let json else { throw APIError.serverError("Invalid JSON response") }
        guard let code = json["code"] as? Int else { throw APIError.serverError("Missing 'code' field") }
        guard code == 0 else {
            let msg = json["message"] as? String ?? "Unknown error"
            throw APIError.serverError(msg)
        }
        guard let dataField = json["data"] else { throw APIError.serverError("Missing 'data' field") }
        if let arr = dataField as? [T], T.self == [String].self {
            return arr as! T
        }
        let data = try JSONSerialization.data(withJSONObject: dataField)
        return try decoder.decode(T.self, from: data)
    }

    /// Check code == 0, ignore the data field
    private func checkOK(_ raw: Data) throws {
        let json = try JSONSerialization.jsonObject(with: raw) as? [String: Any]
        guard let json else { throw APIError.serverError("Invalid JSON") }
        guard let code = json["code"] as? Int else { throw APIError.serverError("Missing 'code'") }
        guard code == 0 else {
            let msg = json["message"] as? String ?? "Unknown error"
            throw APIError.serverError(msg)
        }
    }

    // MARK: - Verb methods

    private func get<T: Decodable>(_ path: String, params: [String: String] = [:]) async throws -> T {
        let url = makeURL(path, params: params)
        let (data, resp) = try await session.data(from: url)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw APIError.serverError("HTTP \(http.statusCode)")
        }
        return try decodeData(data)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        var req = URLRequest(url: makeURL(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: req)
        return try decodeData(data)
    }

    private func postIgnoreResponse(_ path: String, body: [String: Any]) async throws {
        var req = URLRequest(url: makeURL(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: req)
        try checkOK(data)
    }

    private func putIgnoreResponse(_ path: String, body: [String: Any]) async throws {
        var req = URLRequest(url: makeURL(path))
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: req)
        try checkOK(data)
    }
}

enum APIError: Error, LocalizedError {
    case serverError(String)
    case noData

    var errorDescription: String? {
        switch self {
        case .serverError(let msg): return msg
        case .noData: return "服务器返回数据为空"
        }
    }
}

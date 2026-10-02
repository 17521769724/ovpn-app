import Foundation

/// 主控接口错误
enum APIError: LocalizedError {
    case badURL
    case network(String)
    case server(String)
    case decoding(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .badURL: return "主控地址无效"
        case .network(let message): return message
        case .server(let message): return message
        case .decoding(let message): return "数据解析失败：\(message)"
        case .cancelled: return "请求已取消"
        }
    }

    /// 网络请求被系统/下拉刷新取消时不应作为错误提示
    var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }

    /// 归一化任意错误：取消类错误统一识别，避免误报
    static func from(_ error: Error) -> APIError {
        if error is CancellationError { return .cancelled }
        if let apiError = error as? APIError { return apiError }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return .cancelled
        }
        return .network("无法连接主控：\(error.localizedDescription)")
    }
}

/// 主控 HTTP 客户端（Bearer 令牌 + 统一包裹解析）
final class APIClient {
    static let shared = APIClient()

    private var baseURL: String = ""
    private var token: String?
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        session = URLSession(configuration: config)
    }

    /// 更新主控地址（统一去掉尾部斜杠）
    func setBaseURL(_ url: String) {
        baseURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
    }

    var currentBaseURL: String { baseURL }

    func setToken(_ value: String?) {
        token = value
    }

    var currentToken: String? { token }

    private func makeRequest(path: String, method: String, query: [String: String]?, body: [String: Any]?) throws -> URLRequest {
        guard !baseURL.isEmpty, var components = URLComponents(string: baseURL + path) else {
            throw APIError.badURL
        }
        if let query, !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    /// 执行请求并返回 data 段
    func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        query: [String: String]? = nil,
        body: [String: Any]? = nil,
        as type: T.Type
    ) async throws -> T {
        let request = try makeRequest(path: path, method: method, query: query, body: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.from(error)
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        guard let envelope = try? decoder.decode(Envelope<AnyCodableValue>.self, from: data) else {
            if statusCode == 200 {
                throw APIError.decoding("响应不是合法的 JSON")
            }
            throw APIError.server("主控返回异常（HTTP \(statusCode)）")
        }

        if envelope.code != 0 {
            throw APIError.server(envelope.message.isEmpty ? "请求失败" : envelope.message)
        }
        guard let payload = envelope.data else {
            // data 为空但需要返回值的场景（如 {ok:true} 之外的 null）
            if let empty = EmptyPayload() as? T { return empty }
            throw APIError.decoding("响应缺少 data")
        }
        do {
            let raw = try JSONSerialization.data(withJSONObject: payload.value)
            return try decoder.decode(T.self, from: raw)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    /// 无返回体请求
    func requestVoid(
        _ path: String,
        method: String = "POST",
        query: [String: String]? = nil,
        body: [String: Any]? = nil
    ) async throws {
        _ = try await request(path, method: method, query: query, body: body, as: EmptyPayload.self)
    }
}

struct EmptyPayload: Decodable {}

/// 任意 JSON 值包装（用于先解包再按目标类型解析）
struct AnyCodableValue: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodableValue].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodableValue].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
}
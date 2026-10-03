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
        var trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            #if SKIP
            // Kotlin 的 String 没有 removeLast（SkipLib 提供的是 dropLast）
            trimmed = trimmed.dropLast()
            #else
            trimmed.removeLast()
            #endif
        }
        baseURL = trimmed
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

    /// 发送请求并把网络错误统一归一（供 request 使用）
    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw APIError.from(error)
        }
    }

    /// 主控接口统一解码器（snake_case → camelCase）。
    /// 由调用点使用：`APIClient.apiDecoder().decode(X.self, from: data)`
    static func apiDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// 执行请求并返回 data 段。
    ///
    /// Kotlin 泛型在运行时被擦除：泛型函数内既不能用 `T.self` 解码（转译成 `T::class` 会报
    /// reified 错误），也无法让泛型包裹类型在自身 init 中解码 T。因此这里只负责统一解包
    /// 与错误归一，具体类型的解析通过 `decode` 闭包在调用点完成（见 Services.swift）。
    ///
    /// 解包改用 `JSONSerialization`（Skip 的 JSON 值即 Swift 值），避免自定义 Decodable
    /// 包裹类型在转译时被误解析成 companion 成员访问而编译失败。
    func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        query: [String: String]? = nil,
        body: [String: Any]? = nil,
        decode: (Data) throws -> T
    ) async throws -> T {
        let request = try makeRequest(path: path, method: method, query: query, body: body)
        // 通过辅助方法返回元组：Kotlin 端不允许对已声明的 val 二次赋值（原先的 (data, response) = ... 写法无法转译）
        let outcome = try await send(request)
        let data = outcome.0
        let response = outcome.1

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard let json = try? JSONSerialization.jsonObject(with: data),
              let root = json as? [String: Any] else {
            if statusCode == 200 {
                throw APIError.decoding("响应不是合法的 JSON")
            }
            throw APIError.server("主控返回异常（HTTP \(statusCode)）")
        }

        let code = root["code"] as? Int ?? -1
        let message = root["message"] as? String ?? ""
        if code != 0 {
            throw APIError.server(message.isEmpty ? "请求失败" : message)
        }

        guard let payload = root["data"], !(payload is NSNull) else {
            // data 缺失或为 null：无返回体请求（requestVoid → EmptyPayload）
            #if SKIP
            // Kotlin 泛型运行时擦除，无法做 `as? T` 判断；该分支仅 EmptyPayload 场景会走到
            return EmptyPayload() as! T
            #else
            if let empty = EmptyPayload() as? T { return empty }
            throw APIError.decoding("响应缺少 data")
            #endif
        }
        do {
            let raw = try JSONSerialization.data(withJSONObject: payload)
            return try decode(raw)
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
        _ = try await request(path, method: method, query: query, body: body, decode: { _ in EmptyPayload() })
    }
}

struct EmptyPayload: Decodable {}

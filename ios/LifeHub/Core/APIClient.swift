import Foundation

enum APIError: LocalizedError {
    case unauthorized
    case server(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "No autorizado"
        case .server(let detail): return detail
        }
    }
}

/// Cliente fino hacia /api/* — espejo de frontend/src/api.ts.
final class API {
    static let shared = API()

    static let unauthorizedNotification = Notification.Name("lifehub.unauthorized")

    var baseURL: String { AppConfig.baseURL }

    // La clave vive en Keychain (compartido con widgets y App Intents), así
    // que están autenticados sin depender del arranque de la app.
    var token: String {
        get { AppConfig.token }
        set { AppConfig.token = newValue }
    }

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        return URLSession(configuration: cfg)
    }()

    // ── Núcleo ──────────────────────────────────────────────────────────

    func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        body: Encodable? = nil
    ) async throws -> T {
        var req = URLRequest(url: URL(string: baseURL + "/api" + path)!)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 {
            await MainActor.run {
                NotificationCenter.default.post(name: API.unauthorizedNotification, object: nil)
            }
            throw APIError.unauthorized
        }
        guard (200..<300).contains(status) else {
            let text = String(data: data, encoding: .utf8) ?? "Error \(status)"
            throw APIError.server(text)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func upload<T: Decodable>(_ path: String, imageData: Data, filename: String) async throws -> T {
        var req = URLRequest(url: URL(string: baseURL + "/api" + path)!)
        req.httpMethod = "POST"
        let boundary = UUID().uuidString
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw APIError.server(String(data: data, encoding: .utf8) ?? "Error \(status)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// URL absoluta con ?token= para <AsyncImage> (las imágenes no mandan header).
    func imageURL(_ path: String) -> URL? {
        URL(string: baseURL + path + (path.contains("?") ? "&" : "?") + "token=\(token)")
    }
}

/// Permite pasar cualquier Encodable (structs o diccionarios tipados) como body.
struct AnyEncodable: Encodable {
    private let encodeFn: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeFn = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFn(encoder) }
}

/// Body JSON arbitrario estilo diccionario: ["name": .string("x"), ...]
enum JSONValue: Encodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

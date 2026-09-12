import Foundation
struct API {
 let base: String
 init(base: String = "http://127.0.0.1:2132") {self.base = base}
 private let session: URLSession = {
  let c = URLSessionConfiguration.ephemeral
  c.connectionProxyDictionary = [:]
  c.timeoutIntervalForRequest = 35
  return URLSession(configuration: c)
 }()
 struct Envelope<T: Decodable>: Decodable {let code: Int;let msg: String?;let data: T?}
 func call<T: Decodable>(_ path: String, body: Data? = nil, timeout: TimeInterval = 35) async throws -> T {
  guard let url = URL(string: base + path) else {throw APIError(code: 0, message: "地址无效")}
  var request = URLRequest(url: url)
  request.timeoutInterval = timeout
  if let body {request.httpMethod = "POST";request.httpBody = body;request.setValue("application/json", forHTTPHeaderField: "Content-Type")}
  let (data, response) = try await session.data(for: request)
  guard (response as? HTTPURLResponse)?.statusCode == 200 else {throw APIError(code: 0, message: "本地服务响应异常")}
  let envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
  guard envelope.code == 0 else {throw APIError(code: envelope.code, message: envelope.msg ?? "操作失败")}
  if T.self == Empty.self {return Empty() as! T}
  guard let value = envelope.data else {throw APIError(code: 0, message: "本地服务未返回数据")};return value
 }
 func post<T: Encodable>(_ path: String, _ value: T) async throws {let _: Empty = try await call(path, body: JSONEncoder().encode(value))}
 static func query(_ string: String) -> String {string.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""}
}

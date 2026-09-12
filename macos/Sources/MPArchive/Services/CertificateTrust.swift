import Foundation
import Security

enum CertificateTrust {
 static func certificate(from pem: String) throws -> SecCertificate {
  let body = pem.replacingOccurrences(of:"-----BEGIN CERTIFICATE-----",with:"").replacingOccurrences(of:"-----END CERTIFICATE-----",with:"").components(separatedBy:.whitespacesAndNewlines).joined()
  guard let data = Data(base64Encoded:body),let certificate = SecCertificateCreateWithData(nil,data as CFData) else {throw APIError(code:0,message:"本机连接证书格式无效")}
  return certificate
 }
 static func install(_ url: URL) async throws {
  // Trust Settings authentication needs the GUI application's security session.
  // Do not run this inside `osascript ... with administrator privileges`.
  try await Task.detached {
   let cert = try certificate(from:String(contentsOf:url,encoding:.utf8))
   let added = SecItemAdd([kSecClass:kSecClassCertificate,kSecValueRef:cert] as CFDictionary,nil)
   guard added == errSecSuccess || added == errSecDuplicateItem else {throw failure(added)}
   let result = SecTrustSettingsSetTrustSettings(cert,.admin,nil)
   guard result == errSecSuccess else {throw failure(result)}
  }.value
 }
 private static func failure(_ status: OSStatus) -> APIError {
  let detail = SecCopyErrorMessageString(status,nil) as String? ?? "系统返回错误"
  return APIError(code:Int(status),message:"证书授权失败（\(status)）：\(detail)")
 }
}

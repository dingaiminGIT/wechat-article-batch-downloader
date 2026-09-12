import AppKit
import Foundation

@MainActor final class Backend: ObservableObject {
 @Published var running = false
 @Published var connected = false
 @Published var busy = false
 @Published var needsAuthorization = false
 @Published var message = "正在准备本地文章库"
 private var process: Process?
 private var logHandle: FileHandle?
 let dataDirectory: URL
 let downloads: URL
 let binary: URL
 var config: URL {dataDirectory.appendingPathComponent("config.yaml")}
 init() {
  let fm = FileManager.default
  dataDirectory = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MPArticleDownloader")
  downloads = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "downloadDirectory") ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/公众号文章归档").path)
  binary = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/mp_article_batch_downloader")
 }
 static func run(_ binary: String, _ args: [String], environment: [String:String]? = nil) async throws -> (Int32, String) {
  try await Task.detached {
   let p = Process();p.executableURL = URL(fileURLWithPath: binary);p.arguments = args
   if let environment {p.environment = environment}
   let pipe = Pipe();p.standardOutput = pipe;p.standardError = pipe
   try p.run();let data = pipe.fileHandleForReading.readDataToEndOfFile();p.waitUntilExit()
   return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
  }.value
 }
 var environment: [String:String] {
  var env = ProcessInfo.processInfo.environment
  env["MP_ARCHIVE_DATA"] = dataDirectory.path
  env["MP_ARCHIVE_PARENT"] = String(ProcessInfo.processInfo.processIdentifier)
  return env
 }
 func launch(connect: Bool = false) async {
  guard !busy else {return};busy = true;defer {busy = false}
  do {
   try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
   try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
   guard FileManager.default.isWritableFile(atPath: downloads.path) else {throw APIError(code:0,message:"导出目录无法写入，请在设置中选择你有权限的目录，然后重新打开应用")}
   await stopProcess()
   if process?.isRunning == true {throw APIError(code:0,message:"后台仍在收尾，请稍后重试")}
   // JSON is a YAML subset; encoding paths this way avoids escaping and injection problems.
   let configuration: [String:Any] = ["api":["hostname":"127.0.0.1","port":2132,"protocol":"http"],"proxy":["system":connect,"hostname":"127.0.0.1","port":2133,"skipInstallRootCert":true],"download":["dir":downloads.path,"playDoneAudio":false],"mp":["disabled":false,"refreshToken":"mp-archive-local"],"cert":["name":"MP Article Batch Downloader Local CA","file":FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/mp-article-batch-downloader/certs/root-ca.pem").path,"key":FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/mp-article-batch-downloader/certs/root-ca-key.pem").path]]
   try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]).write(to: config, options: .atomic)
   try await restoreNetworkIfNeeded()
   let log = dataDirectory.appendingPathComponent("service.log")
   FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
   logHandle = try FileHandle(forWritingTo: log)
   let p = Process();p.executableURL = binary;p.arguments = ["--config",config.path]
   p.currentDirectoryURL = dataDirectory;p.environment = environment;p.standardOutput = logHandle;p.standardError = logHandle
   process = p;try p.run()
   var ready = false
   for _ in 0..<40 {
    try await Task.sleep(for: .milliseconds(200))
    if !p.isRunning {break}
    if let info: DesktopInfo = try? await API().call("/api/desktop/info"), info.app == "mp-archive-desktop" {ready = true;break}
   }
   guard ready, p.isRunning else {throw APIError(code: 0, message: "服务启动失败，可能已有下载器或墨排采集助手占用端口。请关闭后重试；诊断日志保存在应用数据目录。")}
   running = true;connected = connect;message = connect ? "已连接 · 在微信打开文章即可识别公众号" : "文章库已就绪 · 连接微信后可读取历史"
  } catch {running = false;connected = false;message = error.localizedDescription}
 }
 func connect(authorize: Bool = false) async {
  guard !busy else{return};busy = true;message = "正在检查微信连接环境"
  do {
   let certificate = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/mp-article-batch-downloader/certs/root-ca.pem")
   var result = try await Self.run("/usr/bin/security",["verify-cert","-c",certificate.path])
   if result.0 != 0,authorize {
    NSApp.activate(ignoringOtherApps:true)
    try await CertificateTrust.install(certificate)
    result = try await Self.run("/usr/bin/security",["verify-cert","-c",certificate.path])
   }
   let diagnostic = "\(Date()) authorize=\(authorize) exit=\(result.0)\n\(result.1)"
   try? diagnostic.write(to:dataDirectory.appendingPathComponent("connection.log"),atomically:true,encoding:.utf8)
   if result.0 != 0 {
    needsAuthorization = true
    let detail = result.1.trimmingCharacters(in:.whitespacesAndNewlines)
    message = authorize ? "授权未完成：\(detail.isEmpty ? "系统返回错误 \(result.0)" : String(detail.prefix(1600)))" : "首次连接需要管理员授权。点击“授权并连接”后输入本机密码。"
    busy = false;return
   }
   needsAuthorization = false;busy = false;await launch(connect: true)
  } catch {
   busy = false;needsAuthorization = true;message = error.localizedDescription
   try? "\(Date())\n\(message)".write(to:dataDirectory.appendingPathComponent("connection.log"),atomically:true,encoding:.utf8)
  }
 }
 private static func quote(_ s: String) -> String {"'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"}
 func stopProcess() async {
  if let p = process, p.isRunning {
   p.terminate()
   for _ in 0..<60 {if !p.isRunning {break};try? await Task.sleep(for: .milliseconds(100))}
   if p.isRunning {message = "后台仍在收尾，请稍候";return}
  }
  process = nil;try? logHandle?.close();logHandle = nil;running = false;connected = false
 }
 func restoreNetworkIfNeeded() async throws {
  guard FileManager.default.fileExists(atPath:dataDirectory.appendingPathComponent("proxy-snapshot.json").path) else{return}
  let result = try await Self.run(binary.path,["desktop-recover","--config",config.path],environment:environment)
  guard result.0 == 0 else {throw APIError(code:0,message:"网络配置恢复未完成，请在设置中重试恢复网络")}
 }
 func stop() async {
  guard !busy else{return};busy = true;await stopProcess()
  do {try await restoreNetworkIfNeeded();message = process?.isRunning == true ? "后台仍在收尾，请稍后重试" : "已停止连接并恢复网络配置"}
  catch {message = error.localizedDescription}
  busy = false
 }

 func refreshLiveness() {if running, process?.isRunning != true {running = false;connected = false;message = "后台服务已退出，请重新启动"}}
 func recover() async {
  guard !busy else{return};busy = true
  await stopProcess()
  let result = try? await Self.run(binary.path,["desktop-recover","--config",config.path],environment:environment)
  message = result?.0 == 0 ? "网络配置已恢复，可以重新启动" : "恢复未完成，请查看诊断日志"
  busy = false
 }
}

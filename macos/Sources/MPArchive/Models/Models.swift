import Foundation
import CryptoKit

struct Account: Codable, Identifiable, Hashable {
 let biz: String
 let nickname: String
 let avatar_url: String?
 let is_effective: Bool
 var id: String { biz }
}
struct AccountPage: Decodable { let list: [Account]? }
struct Article: Codable, Identifiable, Hashable {
 let id: String
 let title: String
 let url: String
 let digest: String
 let published: Int64
 var date: Date { Date(timeIntervalSince1970: Double(published)) }
 var filename: String { "\(Self.safeName(title))-\(id).html" }
 static func safeName(_ input: String) -> String {
  let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
  let text = input.unicodeScalars.map { forbidden.contains($0) ? "_" : String($0) }.joined().trimmingCharacters(in: CharacterSet(charactersIn: " ."))
  return text.isEmpty ? "公众号" : String(text.prefix(70))
 }
}
struct ScanOptions: Codable { var biz = ""; var mode = "all"; var limit = 20; var after: Int64 = 0; var before: Int64 = 0; var resume = false }
struct Scan: Decodable {
 var options: ScanOptions?
 var status: String
 var message: String
 var offset: Int
 var pages: Int
 var articles: [Article]
 var updated: Int64
 var source: String? = nil
 var requiresRestart: Bool {source != "native" && (offset > 0 || pages > 0)}
 static let empty = Scan(options: nil, status: "idle", message: "选择范围，读取公众号历史文章", offset: 0, pages: 0, articles: [], updated: 0)
}
struct DownloadItem: Codable, Identifiable {
 let id: String
 let status: String
 let progress: ProgressInfo?
 let meta: Meta?
 let files_exist: Bool?
 let expected_files: [String]?
 let error: String?
 var isLegacy = false
 enum CodingKeys: String, CodingKey {case id,status,progress,meta,files_exist,expected_files,error}
 struct ProgressInfo: Codable {let downloaded: Double?;let speed: Double?;let used: Double?}
 struct Meta: Codable {let opts: Options?;let res: Resource?;let req: Request?}
 struct Options: Codable {let name: String?;let path: String?}
 struct Resource: Codable {let size: Double?}
 struct Request: Codable {let url: String?}
 var availableFiles: [String] {(expected_files ?? []).filter{FileManager.default.isReadableFile(atPath:$0)}}
 var hasText: Bool {availableFiles.contains{$0.hasSuffix(".txt")}}
 // Cache only display metadata; legacy requests can contain WeChat credentials.
 var archiveCopy: DownloadItem {DownloadItem(id:id,status:status,progress:progress,meta:Meta(opts:meta?.opts,res:meta?.res,req:nil),files_exist:files_exist,expected_files:expected_files,error:nil,isLegacy:true)}
 var title: String {meta?.opts?.name ?? "文章"}
 var isActive: Bool { ["running", "ready", "wait"].contains(status) && files_exist != true }
 var isDone: Bool {
  if isLegacy {return status == "done" && !(expected_files ?? []).isEmpty && availableFiles.count == expected_files?.count}
  return status == "done" && files_exist == true
 }
 var statusText: String {
  if isDone {return "已完成"}
  switch status {case "done":return "文件不完整";case "running":return "下载中";case "wait", "ready":return "排队中";case "pause":return "已暂停";case "error":return "下载失败";default:return status}
 }
 var fraction: Double? {guard let size = meta?.res?.size, size > 0 else {return nil};return min(1, max(0, (progress?.downloaded ?? 0) / size))}
}
struct TaskPage: Decodable {let list: [DownloadItem];let total: Int}
struct DownloadBatchProgress: Decodable, Hashable {
 let path: String
 let batch_id: String
 let total: Int
 let completed: Int
 let running: Int
 let queued: Int
 let failed: Int
 let paused: Int
 let missing: Int
 let started_at: Int64
 let finished_at: Int64
 let mode: String?
 var canceled: Int? = nil
 var canceledCount:Int {canceled ?? 0}
 var canResume:Bool {canceledCount == 0 && (paused > 0 || failed > 0)}
 var canStop:Bool {running + queued + paused + failed > 0 && canceledCount == 0}
 var activeCount: Int {running + queued}
 var isActive: Bool {activeCount > 0}
 var started: Date? {started_at > 0 ? Date(timeIntervalSince1970:Double(started_at)/1000) : nil}
 var finished: Date? {finished_at > 0 ? Date(timeIntervalSince1970:Double(finished_at)/1000) : nil}
 func duration(at now: Date) -> TimeInterval {
  guard let started else{return 0}
  return max(0,(finished ?? now).timeIntervalSince(started))
 }
 static func durationText(_ interval: TimeInterval) -> String {
  let seconds = max(0,Int(interval.rounded(.down)))
  let hours = seconds / 3600, minutes = seconds % 3600 / 60, remainder = seconds % 60
  if hours > 0 {return "\(hours)小时\(minutes)分\(remainder)秒"}
  if minutes > 0 {return "\(minutes)分\(remainder)秒"}
  return "\(remainder)秒"
 }
 var modeText: String? {
  switch mode {case "fast":return "快速模式";case "safe":return "安全模式";default:return nil}
 }
 func rateText(at now:Date) -> String? {
  let seconds = duration(at:now)
  guard completed > 0,seconds > 0 else{return nil}
  let rate = Double(completed) * 60 / seconds
  return String(format:"平均 %.1f 篇/分钟",rate)
 }
 func remainingText(at now:Date) -> String? {
  let seconds = duration(at:now)
  let remaining = total - completed
  guard isActive,completed > 2,remaining > 0,seconds > 0 else{return nil}
  return "预计还需 " + Self.durationText(seconds * Double(remaining) / Double(completed))
 }
}
struct DownloadFolder: Identifiable, Hashable {
 let url: URL
 let articleCount: Int
 let size: Int64
 let lastDownloaded: Date?
 let source: String
 let progress: DownloadBatchProgress?
 var id: String {url.path}
 var name: String {url.lastPathComponent}
 var displayName: String {name.replacingOccurrences(of:"-[A-Za-z0-9]{12}$",with:"",options:.regularExpression)}
 var completedCount: Int {
  guard let progress,progress.total > 0 else{return articleCount}
  return min(progress.total,max(progress.completed,articleCount))
 }
 var progressText: String {
  guard let progress,progress.total > 0 else{return detail}
  return "\(completedCount)/\(progress.total) 篇"
 }
 var statusText: String? {
  guard let progress else{return nil}
  var parts:[String] = []
  if progress.running > 0 {parts.append("下载中 \(progress.running)")}
  if progress.queued > 0 {parts.append("排队 \(progress.queued)")}
  if progress.failed > 0 {parts.append("失败 \(progress.failed)")}
  if progress.paused > 0 {parts.append("暂停 \(progress.paused)")}
  if progress.canceledCount > 0 {parts.append(progress.running > 0 ? "终止中 · 当前文章完成后停止" : "已终止 \(progress.canceledCount) 篇")}
  if progress.missing > 0 {parts.append("文件缺失 \(progress.missing)")}
  if parts.isEmpty && completedCount >= progress.total {parts.append("已完成")}
  return parts.joined(separator:" · ")
 }
 var fraction: Double? {guard let progress,progress.total > 0 else{return nil};return Double(completedCount)/Double(progress.total)}
 var detail: String {
  let count = articleCount > 0 ? "\(articleCount) 篇" : "下载文件"
  guard size > 0 else{return count}
  return "\(count) · \(ByteCountFormatter.string(fromByteCount:size,countStyle:.file))"
 }
}
struct DesktopInfo: Decodable {let app: String;let download_dir: String}
struct NativeConnection: Decodable {
 var ready: Bool
 var state: String
 var message: String
 var accounts: [NativeAccount]? = nil
 var article_ready: Bool? = nil
 var canDownload: Bool {ready && article_ready == true}
 var channelConnected: Bool {ready || state == "waiting_profile"}
 var needsReconnect: Bool {["stopped","disconnected","error"].contains(state)}
 var title: String {
  if ready {return (accounts ?? []).isEmpty ? "微信已连接 · 等待公众号" : "微信通道已连接 · 本次识别 \((accounts ?? []).count) 个公众号"}
  switch state {
  case "waiting_miniapp": return "下一步：打开小程序首页"
  case "waiting_profile": return "下一步：打开公众号主页"
  case "disconnected": return "微信连接已失效"
  case "error": return "连接未完成"
  default: return "先连接微信"
  }
 }
 var guidance: String {
  if ready {return canDownload ? "读取只获取文章列表，不会自动下载。点击「开始下载」后才保存正文与图片。" : "请在微信打开目标公众号的一篇文章正文，并保持窗口不关；公众号主页不能代替正文。"}
  if state == "waiting_miniapp" {return "微信 → 发现 → 小程序 → 腾讯文档。停在首页即可；若已经打开，请关闭小程序后重开，不用打开文档。"}
  if state == "waiting_profile" {return "小程序已连接。打开目标公众号的一篇正文，再点击文章里的公众号名称。"}
  if state == "stopped" {return "先点击「连接微信」，再打开腾讯文档小程序首页。无需公众号管理权限。"}
  return message
 }
 static let stopped = NativeConnection(ready:false,state:"stopped",message:"先连接微信，再打开小程序首页")
}
struct NativeAccount: Decodable {let biz: String;let username: String;let nickname: String}
struct ActionNotice: Identifiable {let id = UUID();let title: String;let message: String}
struct DownloadDraft:Identifiable {
 let id = UUID()
 let account:Account
 let articles:[Article]
}
enum DownloadMode: String, CaseIterable, Identifiable {
 case safe, fast
 var id: String {rawValue}
 var title: String {self == .safe ? "稳妥 · 推荐" : "快速 · 试验"}
 var detail: String {self == .safe ? "正文请求间隔至少 2 秒；已有文件跳过。" : "正文请求间隔至少 1 秒，不保证总耗时减半；可能更易遇到微信验证。"}
}
struct ArticleProbe: Decodable {let title: String;let mode: String}
struct Empty: Decodable {}
struct APIError: LocalizedError {let code: Int;let message: String;var errorDescription: String? {message}}

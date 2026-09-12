import Foundation

@MainActor final class LegacyArchive {
 private let api = API(base:"http://127.0.0.1:2122")
 private let cache: URL
 private var attempted = Date.distantPast
 private var fetching = false
 private(set) var tasks: [DownloadItem] = []
 private(set) var notice = ""
 init() {
  cache = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("MPArticleDownloader/legacy-downloads.json")
  if let data = try? Data(contentsOf:cache), let saved = try? JSONDecoder().decode([DownloadItem].self,from:data) {tasks = saved.map{$0.archiveCopy};notice = "旧版记录来自本机缓存"}
 }
 func refresh(force: Bool = false) async {
  guard !fetching, force || Date().timeIntervalSince(attempted) > 15 else{return}
  fetching = true;attempted = Date();defer{fetching = false}
  do {
   var collected: [DownloadItem] = [], page = 1
   while true {
    let result: TaskPage = try await api.call("/api/task/list?status=all&page=\(page)&page_size=1000",timeout:4)
    collected += result.list
    if collected.count >= result.total {break}
    guard !result.list.isEmpty, page < 1000 else {throw APIError(code:0,message:"旧版记录分页未完成")}
    page += 1
   }
   var ids = Set<String>()
   tasks = collected.filter{ids.insert($0.id).inserted}.map{$0.archiveCopy}
   try FileManager.default.createDirectory(at:cache.deletingLastPathComponent(),withIntermediateDirectories:true)
   try JSONEncoder().encode(tasks).write(to:cache,options:.atomic)
   try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:cache.path)
   notice = "已同步旧版记录 · 可直接阅读本机文件，无需重新登录微信"
  } catch {notice = tasks.isEmpty ? "旧版服务未连接，暂无缓存记录" : "旧版服务未连接 · 显示本机缓存，已有文件仍可阅读"}
 }
}

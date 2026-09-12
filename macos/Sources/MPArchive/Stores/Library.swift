import AppKit
import Foundation

@MainActor final class Library: ObservableObject {
 @Published var accounts: [Account] = []
 @Published var selected: String? = "welcome"
 @Published var scan = Scan.empty
 @Published var tasks: [DownloadItem] = []
 @Published var taskTotal = 0
 @Published var taskPage = 1
 @Published var taskFilter = "all"
 @Published var taskSource = "current"
 @Published var taskSearch = ""
 @Published var downloadFolders: [DownloadFolder] = []
 @Published var downloadProgress: [String:DownloadBatchProgress] = [:]
 @Published var legacyTasks: [DownloadItem] = []
 @Published var legacyNotice = ""
 private let legacy = LegacyArchive()
 private var choseTaskSource = false
 @Published var selectedArticles = Set<String>()
 @Published var query = ""
 @Published var options = ScanOptions()
 @Published var after = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
 @Published var before = Date()
 @Published var message = ""
 @Published var queueing = false
 @Published var scanBusy = false
 @Published var downloadMode = UserDefaults.standard.string(forKey:"downloadMode") ?? "safe" {
  didSet {UserDefaults.standard.set(downloadMode,forKey:"downloadMode")}
 }
 private var cancelQueue = false
 private var pollTask: Task<Void,Never>?
 private var ticks = 0
 private var downloadRoot: URL?
 private var lastFolderRefresh = Date.distantPast
 let api = API()
 var account: Account? {accounts.first{$0.biz == selected}}
 var visibleArticles: [Article] {query.isEmpty ? scan.articles : scan.articles.filter{$0.title.localizedCaseInsensitiveContains(query) || $0.digest.localizedCaseInsensitiveContains(query)}}
 func begin(_ backend: Backend) {
  downloadRoot = backend.downloads
  guard pollTask == nil else{return}
  pollTask = Task { [weak self, weak backend] in
   while !Task.isCancelled {
    guard let self, let backend else{return};backend.refreshLiveness()
    if backend.running {await self.refresh()}
    try? await Task.sleep(for: .seconds(2))
   }
  }
 }
 func refresh() async {
  await legacy.refresh()
  legacyTasks = legacy.tasks;legacyNotice = legacy.notice
  refreshDownloadFolders()
  do {
   ticks += 1
   if accounts.isEmpty || ticks % 3 == 0 {
    let page: AccountPage = try await api.call("/api/mp/list?page_size=200")
    accounts = (page.list ?? []).sorted{$0.nickname.localizedStandardCompare($1.nickname) == .orderedAscending}
   }
   if let biz = account?.biz {let state: Scan = try await api.call("/api/desktop/scan?biz=" + API.query(biz));if selected == biz {scan = state}}
   if selected == "downloads" {await refreshTasks();await refreshDownloadProgress();refreshDownloadFolders()}
  } catch {message = error.localizedDescription}
 }
 func selectionChanged() async {
  scan = .empty;selectedArticles = [];query = "";message = ""
  await refresh()
  if let saved = scan.options,["recent","all","date"].contains(saved.mode) {options = saved}
  else {options = ScanOptions()}
 }
 func startScan(resume: Bool = false) async {
  guard let account, !scanBusy else{return};scanBusy = true;defer{scanBusy = false}
  var request = options;request.biz = account.biz;request.resume = resume
  request.after = Int64(Calendar.current.startOfDay(for: after).timeIntervalSince1970)
  request.before = Int64(Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: before))!.timeIntervalSince1970)-1
  do {try await api.post("/api/desktop/scan",request);message = "";await refresh()}
  catch {message = error.localizedDescription}
 }
 func pauseScan() async {guard let account else{return};do {try await api.post("/api/desktop/scan/pause",["biz":account.biz]);message = "正在保存断点并暂停…"}catch{message = error.localizedDescription}}
 func enqueue(selectedOnly: Bool) async {
  guard let account, !queueing else{return}
  let articles = selectedOnly ? scan.articles.filter{selectedArticles.contains($0.id)} : scan.articles
  guard !articles.isEmpty else{return}
  queueing = true;cancelQueue = false;defer{queueing = false}
  let oldest = articles.min{$0.published < $1.published}!
  message = "正在检查历史文章访问权限…"
  do {
   struct ProbeRequest: Encodable {let URL:String}
   let _:ArticleProbe = try await api.call("/api/mp/article/probe",body:JSONEncoder().encode(ProbeRequest(URL:oldest.url)))
  } catch {
   message = "尚未开始下载：\(error.localizedDescription)"
   return
  }
  var created = 0, skipped = 0, failed = 0
  let batchID = UUID().uuidString
  let batchStartedAt = Int64(Date().timeIntervalSince1970 * 1000)
  // Stable account and article IDs make retries and repeated scans idempotent.
  let directory = Article.safeName(account.nickname)
  struct QueueItem: Encodable {
   let url:String;let filename:String;let dir:String;let onExists:String;let extra:[String:String]
   enum CodingKeys:String,CodingKey {case url="URL",filename="Filename",dir="Dir",onExists="on_exists",extra="Extra"}
  }
  struct BatchResult: Decodable {let created: Int;let skipped: Int;let failed: Int}
  for start in stride(from:0,to:articles.count,by:50) {
   if cancelQueue {break}
   let chunk = Array(articles[start..<min(start+50,articles.count)])
  let labels = ["batch_id":batchID,"batch_total":String(articles.count),"batch_started_at":String(batchStartedAt),"account_name":account.nickname,"download_mode":downloadMode]
   let body = chunk.map {QueueItem(url:"officialaccount://"+$0.url,filename:$0.filename,dir:directory,onExists:"skip",extra:labels)}
   do {
    let result: BatchResult = try await api.call("/api/desktop/queue",body:JSONEncoder().encode(body))
    created += result.created;skipped += result.skipped;failed += result.failed
   } catch {failed += chunk.count}
   message = "已处理 \(created + skipped + failed)/\(articles.count) 篇 · 新建 \(created) · 已有 \(skipped) · 失败 \(failed)"
  }
  message = (cancelQueue ? "已停止添加任务。" : "任务添加完成。") + "新建 \(created)，跳过 \(skipped)，失败 \(failed)。可到下载中心查看。"
  if !cancelQueue, let root = downloadRoot {
   let folder = root.appendingPathComponent(directory,isDirectory:true)
   try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
   selected = "downloads"
   NSWorkspace.shared.open(folder)
  }
 }
 func stopQueueing(){cancelQueue = true}
 func refreshTasks() async {
  if !choseTaskSource {
   let current: TaskPage? = try? await api.call("/api/task/list?status=all&page=1&page_size=1")
   if current?.total == 0 && !legacyTasks.isEmpty {taskSource = "legacy"}
   choseTaskSource = true
  }
  if taskSource == "legacy" {
   let filtered = legacyTasks.filter{(taskFilter == "all" || $0.status == taskFilter) && (taskSearch.isEmpty || $0.title.localizedCaseInsensitiveContains(taskSearch) || ($0.meta?.opts?.path ?? "").localizedCaseInsensitiveContains(taskSearch))}
   taskTotal = filtered.count;taskPage = min(taskPage,max(1,(taskTotal+49)/50))
   let start = (taskPage-1)*50
   tasks = Array(filtered.dropFirst(start).prefix(50));return
  }
  do {let source = taskSource, filter = taskFilter, number = taskPage;let page: TaskPage = try await api.call("/api/task/list?status=\(filter)&page=\(number)&page_size=50");guard source == taskSource,filter == taskFilter,number == taskPage else{return};tasks = page.list;taskTotal = page.total}
  catch {message = error.localizedDescription}
 }
 func refreshDownloads(root: URL? = nil) async {
  if let root {downloadRoot = root}
  refreshDownloadFolders(force:true)
  await legacy.refresh(force:true);legacyTasks = legacy.tasks;legacyNotice = legacy.notice
  await refreshTasks();await refreshDownloadProgress();refreshDownloadFolders(force:true)
 }
 func refreshDownloadProgress() async {
  do {
   let summaries:[DownloadBatchProgress] = try await api.call("/api/desktop/download-summary")
   downloadProgress = Dictionary(uniqueKeysWithValues:summaries.map{(URL(fileURLWithPath:$0.path).standardizedFileURL.path,$0)})
  } catch {message = error.localizedDescription}
 }
 func progressForDirectory(_ url:URL) -> DownloadBatchProgress? {
  if let exact = downloadProgress[url.standardizedFileURL.path] {return exact}
  let name = url.lastPathComponent
  return downloadProgress.values
   .filter{URL(fileURLWithPath:$0.path).lastPathComponent.replacingOccurrences(of:"-[A-Za-z0-9]{12}$",with:"",options:.regularExpression) == name}
   .max{$0.started_at < $1.started_at}
 }
 var savedAccountTasks: [DownloadItem] {guard let account else{return []};return legacyTasks.filter{URL(fileURLWithPath:$0.meta?.opts?.path ?? "").lastPathComponent == Article.safeName(account.nickname)}}
 var savedAccountFolder: DownloadFolder? {guard let account else{return nil};let name = Article.safeName(account.nickname);return downloadFolders.first{$0.displayName == name}}
 var savedAccountCount: Int {savedAccountFolder?.articleCount ?? savedAccountTasks.count}
 var hasSavedAccount: Bool {savedAccountFolder != nil || !savedAccountTasks.isEmpty}
	var downloadModeDescription: String {downloadMode == "fast" ? "约每秒 2 篇；遇到短暂访问验证会自动降速重试，持续受限时暂停剩余任务。" : "每秒最多 1 篇，适合长时间、大批量归档。"}
 func openSavedAccountDirectory() {
  guard let account else{return}
  let preferred = savedAccountFolder?.url.path ?? savedAccountTasks.compactMap{$0.meta?.opts?.path}.first
  let fallback = downloadRoot?.appendingPathComponent(Article.safeName(account.nickname),isDirectory:true).path
  guard let path = preferred ?? fallback,FileManager.default.fileExists(atPath:path) else{message = "该公众号的下载目录已移动或删除";return}
  NSWorkspace.shared.open(URL(fileURLWithPath:path,isDirectory:true))
 }
 func refreshDownloadFolders(force: Bool = false) {
  guard force || Date().timeIntervalSince(lastFolderRefresh) > 5 else{return}
  lastFolderRefresh = Date()
  let root = downloadRoot
  let fm = FileManager.default
  var urls = Set<URL>()
  let legacyRoot = fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/公众号文章批量下载",isDirectory:true)
  for parent in [root,legacyRoot].compactMap({$0}) {
   if let children = try? fm.contentsOfDirectory(at:parent,includingPropertiesForKeys:[.isDirectoryKey],options:[.skipsHiddenFiles]) {
    for child in children where (try? child.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) == true {
     var visibleURL = child.standardizedFileURL
     if parent == root,child.lastPathComponent.range(of:"-[A-Za-z0-9]{12}$",options:.regularExpression) != nil {
      let cleanName = child.lastPathComponent.replacingOccurrences(of:"-[A-Za-z0-9]{12}$",with:"",options:.regularExpression)
      let cleanURL = parent.appendingPathComponent(cleanName,isDirectory:true)
      let active = downloadProgress[child.standardizedFileURL.path]?.isActive == true
      if !active,!fm.fileExists(atPath:cleanURL.path),(try? fm.moveItem(at:child,to:cleanURL)) != nil {visibleURL = cleanURL.standardizedFileURL}
     }
     urls.insert(visibleURL)
    }
   }
  }
  if let root {
   for progress in downloadProgress.values {
    let original = URL(fileURLWithPath:progress.path).standardizedFileURL
    guard original.deletingLastPathComponent() == root.standardizedFileURL else{continue}
    let cleanName = original.lastPathComponent.replacingOccurrences(of:"-[A-Za-z0-9]{12}$",with:"",options:.regularExpression)
    let cleanURL = root.appendingPathComponent(cleanName,isDirectory:true).standardizedFileURL
    urls.insert(fm.fileExists(atPath:original.path) ? original : cleanURL)
   }
  }
  downloadFolders = urls.compactMap {url -> DownloadFolder? in
   let outputDirs = ["html","markdown","text"].map{url.appendingPathComponent($0,isDirectory:true)}.filter {
    var isDirectory: ObjCBool = false
    return fm.fileExists(atPath:$0.path,isDirectory:&isDirectory) && isDirectory.boolValue
   }
   let progress = progressForDirectory(url)
   guard !outputDirs.isEmpty || progress != nil else{return nil}
   var htmlNames = Set<String>(),textNames = Set<String>(),latest: Date?
   for directory in outputDirs {
    let names = (try? fm.contentsOfDirectory(atPath:directory.path)) ?? []
    for name in names where !name.hasPrefix(".") {
     let file = URL(fileURLWithPath:name)
     if file.pathExtension.lowercased() == "html" {htmlNames.insert(file.deletingPathExtension().lastPathComponent)}
     if file.pathExtension.lowercased() == "txt" {textNames.insert(file.deletingPathExtension().lastPathComponent)}
    }
    if let date = (try? fm.attributesOfItem(atPath:directory.path)[.modificationDate]) as? Date,latest == nil || date > latest! {latest = date}
   }
   let source = root != nil && url.path.hasPrefix(root!.standardizedFileURL.path) ? "新应用" : "旧工具"
   return DownloadFolder(url:url,articleCount:htmlNames.isEmpty ? textNames.count : htmlNames.count,size:0,lastDownloaded:latest,source:source,progress:progress)
  }.sorted {(left,right) in (left.lastDownloaded ?? .distantPast) > (right.lastDownloaded ?? .distantPast)}
 }
 func taskAction(_ action: String, id: String) async {
  do {try await api.post("/api/task/"+action,["id":id]);await refreshTasks()}
  catch {message = error.localizedDescription}
 }
 func copyLink(_ article: Article) {NSPasteboard.general.clearContents();NSPasteboard.general.setString(article.url,forType:.string);message = "文章链接已复制"}
}

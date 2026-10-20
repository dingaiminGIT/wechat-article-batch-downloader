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
 @Published var notice: ActionNotice?
 @Published var downloadDraft:DownloadDraft?
 @Published var downloadBatches:[DownloadBatchProgress] = []
 @Published var controllingBatch:String?
 @Published var stopBatchConfirmation:DownloadBatchProgress?
 private var submittingBatchID:String?
 @Published var queueStatus = ""
 @Published var openingDirectory = false
 @Published var downloadMode: DownloadMode = DownloadMode(rawValue:UserDefaults.standard.string(forKey:"nativeDownloadMode") ?? "safe") ?? .safe {
  didSet {UserDefaults.standard.set(downloadMode.rawValue,forKey:"nativeDownloadMode")}
 }
 @Published var queueing = false
 @Published var scanBusy = false
 @Published var nativeConnection = NativeConnection.stopped
 @Published var nativeBusy = false
 private var cancelQueue = false
 private var pollTask: Task<Void,Never>?
 private var ticks = 0
 private var connectionRevision = 0
 private var downloadRoot: URL?
 private var lastFolderRefresh = Date.distantPast
 @Published private(set) var refreshingFolders = false
 let api = API()
 var account: Account? {accounts.first{$0.biz == selected}}
 var visibleArticles: [Article] {query.isEmpty ? scan.articles : scan.articles.filter{$0.title.localizedCaseInsensitiveContains(query) || $0.digest.localizedCaseInsensitiveContains(query)}}
 func begin(_ backend: Backend) {
  downloadRoot = backend.downloads
  guard pollTask == nil else{return}
  pollTask = Task { [weak self, weak backend] in
   while !Task.isCancelled {
    guard let self, let backend else{return};backend.refreshLiveness()
    if backend.running {await self.refresh()}else{self.nativeConnection = .stopped}
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
   if ticks % 3 == 0 && !nativeBusy {await refreshNativeStatus()}
   if accounts.isEmpty || selected == "welcome" || ticks % 3 == 0 {
    let page: AccountPage = try await api.call("/api/mp/list?page_size=200")
    accounts = (page.list ?? []).sorted{$0.nickname.localizedStandardCompare($1.nickname) == .orderedAscending}
   }
   if let biz = account?.biz {let state: Scan = try await api.call("/api/desktop/scan?biz=" + API.query(biz));if selected == biz {scan = state}}
   await refreshDownloadProgress()
   if selected == "downloads" {await refreshTasks();refreshDownloadFolders()}
  } catch {message = error.localizedDescription}
 }
 func selectionChanged() async {
  scan = .empty;selectedArticles = [];query = "";message = ""
  await refresh()
  if let saved = scan.options,["recent","all","date"].contains(saved.mode) {options = saved}
  else {options = ScanOptions()}
 }
 func connectNative() async {
  guard !nativeBusy else{return};connectionRevision += 1;nativeBusy=true;defer{nativeBusy=false}
  do {nativeConnection=try await api.call("/api/desktop/native/connect",body:Data("{}".utf8),timeout:60);message="";await refresh()}
  catch {nativeConnection=NativeConnection(ready:false,state:"error",message:error.localizedDescription);message=error.localizedDescription}
 }
 func disconnectNative() async {
  guard !nativeBusy else{return};connectionRevision += 1;nativeBusy=true;defer{nativeBusy=false}
  do {try await api.post("/api/desktop/native/disconnect",[String:String]());nativeConnection = .stopped}
  catch {message=error.localizedDescription}
 }
 func refreshNativeStatus() async {
  guard !nativeBusy else{return}
  let revision = connectionRevision
  let status: NativeConnection = (try? await api.call("/api/desktop/native/status")) ?? NativeConnection(ready:false,state:"error",message:"连接状态暂不可用，请检查本地服务后重试。")
  if !nativeBusy && revision == connectionRevision {nativeConnection = status}
 }
 var canReadNative: Bool {nativeConnection.ready && !nativeBusy}
 var canDownloadNative: Bool {nativeConnection.canDownload && !nativeBusy}
 func showNotice(_ title:String,_ detail:String) {notice = ActionNotice(title:title,message:detail)}
 func accountConnectionLabel(_ biz: String) -> String {
  (nativeConnection.accounts ?? []).contains{$0.biz == biz} && nativeConnection.channelConnected ? "本次已识别" : "已保存的公众号"
 }
 func startScan(resume: Bool = false) async {
  guard canReadNative else {showNotice("需要连接微信才能更新列表",nativeConnection.guidance + "\n已有文件可以离线打开，无需重新读取。");return}
  guard let account, !scanBusy else{return};scanBusy = true;defer{scanBusy = false}
  guard options.mode != "date" || after <= before else {message = "开始日期不能晚于结束日期";return}
  guard options.mode != "recent" || (1...10000).contains(options.limit) else {message = "最近文章篇数请填写 1～10000";return}
  var request = options;request.biz = account.biz;request.resume = resume
  request.after = Int64(Calendar.current.startOfDay(for: after).timeIntervalSince1970)
  request.before = Int64(Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: before))!.timeIntervalSince1970)-1
  do {try await api.post("/api/desktop/scan",request);message = "";await refresh()}
  catch {message = error.localizedDescription}
 }
 func pauseScan() async {guard let account else{return};do {try await api.post("/api/desktop/scan/pause",["biz":account.biz]);message = "正在保存断点并暂停…"}catch{message = error.localizedDescription}}
 func requestDownload(selectedOnly:Bool) {
  guard let account,!queueing else{return}
  let articles = selectedOnly ? scan.articles.filter{selectedArticles.contains($0.id)} : scan.articles
  guard !articles.isEmpty else{return}
  downloadDraft = DownloadDraft(account:account,articles:articles)
 }
 func confirmDownload(_ draft:DownloadDraft) async {
  downloadDraft = nil
  await enqueue(draft:draft)
 }
 func enqueue(selectedOnly:Bool) async {
  guard let account else {return}
  let articles = selectedOnly ? scan.articles.filter{selectedArticles.contains($0.id)} : scan.articles
  await enqueue(draft:DownloadDraft(account:account,articles:articles))
 }
 private func enqueue(draft:DownloadDraft) async {
  guard canDownloadNative else {showNotice("尚未开始下载",nativeConnection.ready ? "文章列表已读到，但当前没有可用的微信正文窗口。请在微信打开目标公众号的一篇正文并保持不关，然后重试。" : nativeConnection.guidance);return}
  guard !queueing else{return}
  let account=draft.account, articles=draft.articles
  guard !articles.isEmpty else{return}
  queueing = true;cancelQueue = false;defer{queueing = false;queueStatus = "";submittingBatchID=nil}
  let oldest = articles.min{$0.published < $1.published}!
  queueStatus = "正在检查正文能否访问，尚未创建下载任务…"
  let mode = downloadMode.rawValue
  do {
   struct ProbeRequest: Encodable {let URL:String}
   let _:ArticleProbe = try await api.call("/api/mp/article/probe",body:JSONEncoder().encode(ProbeRequest(URL:oldest.url)))
  } catch {
   showNotice("尚未开始下载",error.localizedDescription)
   return
  }
  if cancelQueue {showNotice("已取消","没有创建下载任务。");return}
  var created = 0, skipped = 0, failed = 0
  let batchID = UUID().uuidString
  submittingBatchID=batchID
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
  let labels = ["batch_id":batchID,"batch_total":String(articles.count),"batch_started_at":String(batchStartedAt),"account_name":account.nickname,"download_mode":mode]
   let body = chunk.map {QueueItem(url:"officialaccount://"+$0.url,filename:$0.filename,dir:directory,onExists:"skip",extra:labels)}
   do {
    let result: BatchResult = try await api.call("/api/desktop/queue",body:JSONEncoder().encode(body))
    created += result.created;skipped += result.skipped;failed += result.failed
    if created>0 {selected="downloads";await refreshDownloadProgress();refreshDownloadFolders(force:true)}
   } catch {showNotice("添加下载任务未完成","已成功提交 \(created) 篇、跳过 \(skipped) 篇。当前批次提交失败：\(error.localizedDescription)\n请到下载中心核对后重试，已有文件会跳过。");return}
   queueStatus = "已处理 \(created + skipped + failed)/\(articles.count) 篇 · 新建 \(created) · 已有 \(skipped) · 失败 \(failed)"
  }
  if created > 0 {selected = "downloads";await refreshDownloadProgress();refreshDownloadFolders(force:true)}
  if !cancelQueue {showNotice(created > 0 ? "下载任务已添加" : "没有新增下载任务","新建 \(created) 篇，已有跳过 \(skipped) 篇，失败 \(failed) 篇。" + (created > 0 ? "\n请在下载中心查看完成情况，可暂停、继续或终止下载。" : "\n本次没有开始新的正文下载。"))}
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
    let summaries:[DownloadBatchProgress] = try await api.call("/api/desktop/download-summary?all=1")
   downloadBatches = summaries
   var latest:[String:DownloadBatchProgress] = [:]
   for batch in summaries {let path=URL(fileURLWithPath:batch.path).standardizedFileURL.path;if latest[path] == nil {latest[path]=batch}}
   downloadProgress=latest
  } catch {message = error.localizedDescription}
 }
 func controlBatch(_ batch:DownloadBatchProgress,action:String) async {
  guard controllingBatch == nil else{return}
  if action=="resume" && !canDownloadNative {showNotice("暂不能继续下载",nativeConnection.guidance);return}
  if action != "resume",submittingBatchID==batch.batch_id {cancelQueue=true}
  controllingBatch=batch.batch_id;defer{controllingBatch=nil}
  struct Reply:Decodable {let changed:Int;let finishing:Int}
  do {
   let reply:Reply = try await api.call("/api/desktop/batch-control",body:JSONEncoder().encode(["batch_id":batch.batch_id,"path":batch.path,"action":action]))
   let title=action=="pause" ? "已暂停后续下载" : action=="stop" ? "已终止后续下载" : "已继续下载"
   message="\(title)：\(reply.changed) 篇。" + (reply.finishing>0 && action != "resume" ? "当前正在导出的 \(reply.finishing) 篇会完成后停止；已保存文件保留。" : "已保存文件保留。")
   await refreshDownloadProgress();refreshDownloadFolders(force:true)
  } catch {showNotice("批次操作未完成",error.localizedDescription)}
 }
 func progressForDirectory(_ url:URL) -> DownloadBatchProgress? {
  if let exact = downloadProgress[url.standardizedFileURL.path] {return exact}
  let name = url.lastPathComponent
  return downloadProgress.values
   .filter{URL(fileURLWithPath:$0.path).lastPathComponent.replacingOccurrences(of:"-[A-Za-z0-9]{12}$",with:"",options:.regularExpression) == name}
   .max{$0.started_at < $1.started_at}
 }
 var savedAccountTasks: [DownloadItem] {guard let account else{return []};return legacyTasks.filter{URL(fileURLWithPath:$0.meta?.opts?.path ?? "").lastPathComponent == Article.safeName(account.nickname)}}
 var savedAccountFolder: DownloadFolder? {guard let account else{return nil};let name = Article.safeName(account.nickname);return downloadFolders.filter{$0.displayName == name}.max{$0.articleCount < $1.articleCount}}
 var savedAccountCount: Int {savedAccountFolder?.articleCount ?? 0}
 var hasSavedAccount: Bool {savedAccountCount > 0}
 var hasAccountHistory: Bool {savedAccountFolder != nil || !savedAccountTasks.isEmpty}
 var downloadModeDescription: String {downloadMode.detail + "遇到访问验证，两种模式都会暂停整批。"}
 func openSavedAccountDirectory() {
  guard let account else{return}
  let folders = downloadFolders.filter{$0.displayName == Article.safeName(account.nickname)}.sorted{$0.articleCount > $1.articleCount}.map{$0.url}
  let old = savedAccountTasks.compactMap{$0.meta?.opts?.path}.map{URL(fileURLWithPath:$0,isDirectory:true)}
  let fallback = downloadRoot.map{$0.appendingPathComponent(Article.safeName(account.nickname),isDirectory:true)}
  openDirectoryCandidates(folders + old + [fallback].compactMap{$0})
 }
 func openDirectory(_ url: URL) {openDirectoryCandidates([url])}
 private func openDirectoryCandidates(_ urls:[URL]) {
  guard !openingDirectory else{return};openingDirectory = true
  Task {
   let existing = await Task.detached(priority:.userInitiated) {DirectoryAccess.firstExisting(urls)}.value
   guard let existing else {
    openingDirectory = false
    showNotice("未找到本地目录","历史下载记录仍在，但这些路径中的目录已移动或删除。记录不等于文件；重新连接微信不会恢复本地文件。\n" + urls.prefix(3).map{$0.path}.joined(separator:"\n"))
    return
   }
   let config = NSWorkspace.OpenConfiguration();config.activates = true
   NSWorkspace.shared.open([existing],withApplicationAt:URL(fileURLWithPath:"/System/Library/CoreServices/Finder.app"),configuration:config) { [weak self] _, error in
    Task { @MainActor in
     guard let self else{return};self.openingDirectory = false
     if let error {self.showNotice("无法打开目录",error.localizedDescription + "\n" + existing.path)}
     else {self.message = "已在 Finder 打开：" + existing.path}
    }
   }
  }
 }
 func refreshDownloadFolders(force: Bool = false) {
  guard !refreshingFolders, force || Date().timeIntervalSince(lastFolderRefresh) > 5 else{return}
  refreshingFolders = true;lastFolderRefresh = Date()
  let root = downloadRoot, progress = downloadProgress
  Task { [weak self] in
   let folders = await Task.detached(priority:.utility) {
    DownloadFolderScanner.scan(root:root,progress:progress)
   }.value
   guard let self else{return}
   self.downloadFolders = folders;self.refreshingFolders = false
  }
 }
 func taskAction(_ action: String, id: String) async {
  do {try await api.post("/api/task/"+action,["id":id]);await refreshTasks()}
  catch {message = error.localizedDescription}
 }
 func copyLink(_ article: Article) {NSPasteboard.general.clearContents();NSPasteboard.general.setString(article.url,forType:.string);message = "文章链接已复制"}
}

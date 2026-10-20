import XCTest
@testable import MPArchive
final class ModelsTests: XCTestCase {
 @MainActor func testDownloadRequiresConfirmationAndSnapshotsSelection() {
  let library = Library()
  library.accounts = [Account(biz:"confirm-test",nickname:"确认测试",avatar_url:nil,is_effective:true)]
  library.selected = "confirm-test"
  let article = Article(id:"one",title:"测试文章",url:"https://example.invalid/article",digest:"",published:0)
  library.scan = Scan(status:"done",message:"",offset:0,pages:1,articles:[article],updated:0)
  library.requestDownload(selectedOnly:false)
  XCTAssertEqual(library.downloadDraft?.articles.map(\.id),["one"])
  XCTAssertFalse(library.queueing,"opening confirmation must not submit a batch")
  library.scan.articles=[]
  XCTAssertEqual(library.downloadDraft?.articles.count,1,"confirmation must retain the displayed selection")
  library.downloadDraft=nil
  XCTAssertFalse(library.queueing,"cancel must not submit a batch")
 }
 func testTerminatedBatchCannotResume() throws {
  let data=Data(#"{"path":"/tmp/test","batch_id":"test","total":3,"completed":1,"running":0,"queued":0,"failed":0,"paused":2,"missing":0,"started_at":1,"finished_at":0}"#.utf8)
  var batch=try JSONDecoder().decode(DownloadBatchProgress.self,from:data)
  XCTAssertTrue(batch.canResume)
  XCTAssertTrue(batch.canStop)
  batch.canceled=2
  XCTAssertFalse(batch.canResume)
  XCTAssertFalse(batch.canStop)
 }
 func testDirectoryLookupSkipsMissingOldPath() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  defer {try? FileManager.default.removeItem(at:root)}
  let missing = root.appendingPathComponent("moved",isDirectory:true)
  XCTAssertEqual(DirectoryAccess.firstExisting([missing,root]),root)
  XCTAssertNil(DirectoryAccess.firstExisting([missing]))
  XCTAssertFalse(FileManager.default.fileExists(atPath:missing.path),"opening history must not create an empty replacement directory")
 }
 @MainActor func testMissingHistoryDoesNotCountAsSavedFiles() {
  let library = Library()
  library.accounts = [Account(biz:"test",nickname:"测试",avatar_url:nil,is_effective:false)]
  library.selected = "test"
  library.legacyTasks = [DownloadItem(id:"old",status:"done",progress:nil,meta:.init(opts:.init(name:"old",path:"/missing/测试"),res:nil,req:nil),files_exist:true,expected_files:["/missing/测试/text/old.txt"],error:nil,isLegacy:true)]
  XCTAssertEqual(library.savedAccountCount,0)
  XCTAssertFalse(library.hasSavedAccount)
  XCTAssertTrue(library.hasAccountHistory)
 }
 func testReadyListDoesNotImplyReadyBody() throws {
  let noBody = try JSONDecoder().decode(NativeConnection.self,from:Data(#"{"ready":true,"state":"ready","message":"","accounts":[],"article_ready":false}"#.utf8))
  XCTAssertFalse(noBody.canDownload)
  var body = noBody;body.article_ready = true
  XCTAssertTrue(body.canDownload)
  body.ready = false
  XCTAssertFalse(body.canDownload)
 }
 func testConnectedTitleReportsObservedAccountsNotUniversalReadiness() {
  let connection = NativeConnection(ready:true,state:"ready",message:"",accounts:[NativeAccount(biz:"test",username:"gh_test",nickname:"Test")],article_ready:true)
  XCTAssertEqual(connection.title,"微信通道已连接 · 本次识别 1 个公众号")
  XCTAssertFalse(connection.title.contains("下载已就绪"))
 }
 func testFolderScannerIsReadOnlyAndCountsFiles() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
  let folder = root.appendingPathComponent("测试公众号-AbCdEf123456",isDirectory:true)
  let html = folder.appendingPathComponent("html",isDirectory:true)
  try FileManager.default.createDirectory(at:html,withIntermediateDirectories:true)
  defer {try? FileManager.default.removeItem(at:root)}
  try "正文".write(to:html.appendingPathComponent("article.html"),atomically:true,encoding:.utf8)
  let folders = DownloadFolderScanner.scan(root:root,progress:[:],legacyRoot:nil)
  XCTAssertEqual(folders.count,1)
  XCTAssertEqual(folders.first?.articleCount,1)
  XCTAssertEqual(folders.first?.displayName,"测试公众号")
  XCTAssertTrue(FileManager.default.fileExists(atPath:folder.path),"directory scanning must not rename user files")
 }
 func testNativeConnectionStagesAreActionable() throws {
  let stopped = NativeConnection.stopped
  XCTAssertTrue(stopped.needsReconnect)
  XCTAssertFalse(stopped.channelConnected)
  let waiting = NativeConnection(ready:false,state:"waiting_miniapp",message:"")
  XCTAssertFalse(waiting.needsReconnect)
  XCTAssertTrue(waiting.guidance.contains("首页"))
  XCTAssertTrue(waiting.guidance.contains("不用打开文档"))
  let profile = NativeConnection(ready:false,state:"waiting_profile",message:"")
  XCTAssertTrue(profile.channelConnected)
  XCTAssertFalse(profile.ready)
  let ready = try JSONDecoder().decode(NativeConnection.self,from:Data(#"{"ready":true,"state":"ready","message":"","accounts":[]}"#.utf8))
  XCTAssertEqual(ready.title,"微信已连接 · 等待公众号")
  let disconnected = NativeConnection(ready:false,state:"disconnected",message:"微信会话已变化")
  XCTAssertTrue(disconnected.needsReconnect)
  XCTAssertEqual(disconnected.guidance,"微信会话已变化")
 }
 @MainActor func testDisconnectedActionsDoNotStartWork() async {
  let library = Library()
  await library.startScan()
  XCTAssertFalse(library.scanBusy)
  XCTAssertTrue(library.notice?.message.contains(NativeConnection.stopped.guidance) == true)
  await library.enqueue(selectedOnly:false)
  XCTAssertFalse(library.queueing)
  XCTAssertFalse(library.canReadNative)
 }
 func testLegacyCacheExcludesRequestCredentials() throws {
  let data = Data(#"{"id":"old","status":"done","meta":{"opts":{"name":"saved","path":"/tmp"},"req":{"url":"https://mp.weixin.qq.com/s?key=private-token"}},"error":"private-error"}"#.utf8)
  let item = try JSONDecoder().decode(DownloadItem.self,from:data).archiveCopy
  let cached = try JSONEncoder().encode(item)
  XCTAssertTrue(item.isLegacy)
  XCTAssertFalse(String(decoding:cached,as:UTF8.self).contains("private"))
  XCTAssertEqual(try JSONDecoder().decode(DownloadItem.self,from:cached).archiveCopy.title,"saved")
 }
 func testPreviewRequiresReadableTextAndHandlesRemovedFile() throws {
  let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".txt")
  try "正文".write(to:path,atomically:true,encoding:.utf8)
  defer {try? FileManager.default.removeItem(at:path)}
  let item = DownloadItem(id:"test",status:"done",progress:nil,meta:nil,files_exist:true,expected_files:[path.path],error:nil)
  XCTAssertTrue(item.hasText)
  XCTAssertTrue(item.archiveCopy.isDone)
  try FileManager.default.removeItem(at:path)
  XCTAssertFalse(item.hasText)
  XCTAssertFalse(item.archiveCopy.isDone)
 }
 func testFileNameIsStableAcrossScans() {let a = Article(id:"abc123",title:"第 1.2 版 / 新文章",url:"https://mp.weixin.qq.com/s/test",digest:"",published:0);XCTAssertEqual(a.filename,"第 1.2 版 _ 新文章-abc123.html");XCTAssertFalse(Article.safeName("../../bad/path").contains("/"))}
 func testCompletedTaskRequiresFiles() throws {let data = Data(#"{"id":"1","status":"done","files_exist":false}"#.utf8);let task = try JSONDecoder().decode(DownloadItem.self,from:data);XCTAssertFalse(task.isDone);XCTAssertEqual(task.statusText,"文件不完整")}
 func testIdleScanDecodes() throws {let data = Data(#"{"status":"idle","message":"","offset":0,"pages":0,"articles":[],"updated":0}"#.utf8);XCTAssertTrue(try JSONDecoder().decode(Scan.self,from:data).articles.isEmpty)}
 func testDownloadFolderHidesTechnicalSuffixAndFormatsProgress() {
  let progress = DownloadBatchProgress(path:"/tmp/快刀青衣-MjM5NjQyMjE1",batch_id:"",total:297,completed:63,running:1,queued:233,failed:0,paused:0,missing:0,started_at:1_000,finished_at:0,mode:"safe")
  let folder = DownloadFolder(url:URL(fileURLWithPath:progress.path),articleCount:63,size:0,lastDownloaded:nil,source:"新应用",progress:progress)
  XCTAssertEqual(folder.displayName,"快刀青衣")
  XCTAssertEqual(folder.progressText,"63/297 篇")
  XCTAssertEqual(folder.statusText,"下载中 1 · 排队 233")
  XCTAssertEqual(progress.modeText,"安全模式")
  XCTAssertEqual(folder.fraction!,63.0/297.0,accuracy:0.0001)
  XCTAssertEqual(DownloadBatchProgress.durationText(312),"5分12秒")
 }
}

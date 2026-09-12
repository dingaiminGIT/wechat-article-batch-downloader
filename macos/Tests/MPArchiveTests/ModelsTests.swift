import XCTest
@testable import MPArchive
final class ModelsTests: XCTestCase {
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

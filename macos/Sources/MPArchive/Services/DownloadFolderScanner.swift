import Foundation

// Filesystem reads can wait on macOS privacy checks or an unavailable volume.
// Call only from a background task; never block the app's main actor.
enum DownloadFolderScanner {
 static func scan(root: URL?, progress: [String:DownloadBatchProgress], legacyRoot: URL? = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/公众号文章批量下载",isDirectory:true)) -> [DownloadFolder] {
  let fm = FileManager.default
  var urls = Set<URL>()
  for parent in [root,legacyRoot].compactMap({$0}) {
   if let children = try? fm.contentsOfDirectory(at:parent,includingPropertiesForKeys:[.isDirectoryKey],options:[.skipsHiddenFiles]) {
    for child in children where (try? child.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) == true {
     urls.insert(child.standardizedFileURL)
    }
   }
  }
  if let root {
   for entry in progress.values {
    let url = URL(fileURLWithPath:entry.path).standardizedFileURL
    if url.deletingLastPathComponent() == root.standardizedFileURL {urls.insert(url)}
   }
  }
  return urls.compactMap {url -> DownloadFolder? in
   let entry = progress[url.path] ?? progress.values.filter {
    URL(fileURLWithPath:$0.path).lastPathComponent.replacingOccurrences(of:"-[A-Za-z0-9]{12}$",with:"",options:.regularExpression) == url.lastPathComponent
   }.max{$0.started_at < $1.started_at}
   let outputDirs = ["html","markdown","text"].map{url.appendingPathComponent($0,isDirectory:true)}.filter {
    var isDirectory: ObjCBool = false
    return fm.fileExists(atPath:$0.path,isDirectory:&isDirectory) && isDirectory.boolValue
   }
   guard !outputDirs.isEmpty || entry != nil else{return nil}
   var htmlNames = Set<String>(),textNames = Set<String>(),latest: Date?
   for directory in outputDirs {
    for name in (try? fm.contentsOfDirectory(atPath:directory.path)) ?? [] where !name.hasPrefix(".") {
     let file = URL(fileURLWithPath:name)
     if file.pathExtension.lowercased() == "html" {htmlNames.insert(file.deletingPathExtension().lastPathComponent)}
     if file.pathExtension.lowercased() == "txt" {textNames.insert(file.deletingPathExtension().lastPathComponent)}
    }
    if let date = (try? fm.attributesOfItem(atPath:directory.path)[.modificationDate]) as? Date,latest == nil || date > latest! {latest = date}
   }
   let source = root != nil && url.deletingLastPathComponent() == root!.standardizedFileURL ? "新应用" : "旧工具"
   return DownloadFolder(url:url,articleCount:htmlNames.isEmpty ? textNames.count : htmlNames.count,size:0,lastDownloaded:latest,source:source,progress:entry)
  }.sorted {($0.lastDownloaded ?? .distantPast) > ($1.lastDownloaded ?? .distantPast)}
 }
}

import SwiftUI
import AppKit

struct DownloadsView: View {
 @ObservedObject var library: Library
 @ObservedObject var backend: Backend
 var body: some View {
  VStack(alignment:.leading,spacing:0) {
   HStack {
    VStack(alignment:.leading,spacing:6) {
     Text("下载中心").font(.title2.weight(.semibold))
     Text("每个公众号一个文件夹；这里记录下载时间、速度和结果。").font(.callout).foregroundStyle(.secondary)
    }
    Spacer()
    Button("打开下载根目录"){NSWorkspace.shared.open(backend.downloads)}
    Button("刷新"){library.refreshDownloadFolders(force:true);Task{await library.refreshDownloads(root:backend.downloads)}}
   }.padding(24)
   Divider()
   if library.downloadFolders.isEmpty {
    ContentUnavailableView("还没有下载目录",systemImage:"folder.badge.plus",description:Text("下载公众号文章后，会按公众号显示在这里。")).frame(maxWidth:.infinity,maxHeight:.infinity)
   } else {
    ScrollView {
     TimelineView(.periodic(from:.now,by:1)) {timeline in
      LazyVStack(spacing:0) {
       ForEach(library.downloadFolders) {folder in
        downloadRow(folder,now:timeline.date)
        Divider()
       }
      }
     }
    }
   }
   Divider()
   HStack {Text("共 \(library.downloadFolders.count) 个公众号目录 · 文件保存在本机").font(.caption).foregroundStyle(.secondary);Spacer()}.padding(16)
  }
  .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top)
  .navigationTitle("下载中心")
  .onAppear {library.refreshDownloadFolders(force:true)}
  .task {await library.refreshDownloads(root:backend.downloads)}
 }
 @ViewBuilder private func downloadRow(_ folder:DownloadFolder,now:Date) -> some View {
  let hasFailures = (folder.progress?.failed ?? 0) > 0
  HStack(spacing:16) {
   Image(systemName:"folder.fill").font(.title).foregroundStyle(.tint).frame(width:38)
   VStack(alignment:.leading,spacing:7) {
    Text(folder.displayName).font(.headline).lineLimit(1)
    HStack(spacing:8) {
     Text(folder.progressText).monospacedDigit()
     if let status = folder.statusText {Text(status).foregroundStyle(hasFailures ? Color.orange : Color.secondary)}
     if let mode = folder.progress?.modeText {Text(mode).padding(.horizontal,7).padding(.vertical,2).background(.quaternary,in:Capsule())}
    }.font(.caption).foregroundStyle(.secondary)
    if let fraction = folder.fraction {ProgressView(value:fraction).tint(hasFailures && folder.progress?.isActive == false ? .orange : .accentColor).frame(maxWidth:520)}
    if let progress = folder.progress,let started = progress.started {
     HStack(spacing:8) {
      Text("开始 \(started.formatted(date:.abbreviated,time:.shortened))")
      if let finished = progress.finished {Text("结束 \(finished.formatted(date:.omitted,time:.shortened))");Text("总耗时 \(DownloadBatchProgress.durationText(progress.duration(at:now)))");if let rate=progress.rateText(at:now){Text(rate)}}
      else {Text("已用时 \(DownloadBatchProgress.durationText(progress.duration(at:now)))");if let remaining=progress.remainingText(at:now){Text(remaining)}}
     }.font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
    } else if let date = folder.lastDownloaded {
     Text("最近下载 \(date.formatted(date:.abbreviated,time:.shortened))").font(.caption2).foregroundStyle(.tertiary)
    }
   }
   Spacer()
   Button("打开目录"){try? FileManager.default.createDirectory(at:folder.url,withIntermediateDirectories:true);NSWorkspace.shared.open(folder.url)}.buttonStyle(.borderedProminent)
  }.padding(.vertical,16).padding(.horizontal,24)
 }
}

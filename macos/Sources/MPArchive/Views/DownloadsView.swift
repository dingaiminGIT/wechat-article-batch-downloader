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
    Button("打开下载根目录"){library.openDirectory(backend.downloads)}.disabled(library.openingDirectory)
    Button("刷新"){library.refreshDownloadFolders(force:true);Task{await library.refreshDownloads(root:backend.downloads)}}
   }.padding(24)
   if library.queueing {HStack {ProgressView().controlSize(.small);Text(library.queueStatus);Spacer();Button("停止添加（已提交的继续）"){library.stopQueueing()}}.padding(.horizontal,24).padding(.bottom,12)}
   Divider()
   if library.downloadFolders.isEmpty && library.downloadBatches.isEmpty && library.refreshingFolders {
    VStack(spacing:12) {
     ProgressView()
     Text("正在检查本地下载目录…").font(.headline)
     Text("若系统询问目录访问权限，请按需允许。你可以继续连接微信或浏览其他页面。").font(.callout).foregroundStyle(.secondary)
    }.frame(maxWidth:.infinity,maxHeight:.infinity).padding()
   } else if library.downloadFolders.isEmpty && library.downloadBatches.isEmpty {
    ContentUnavailableView("还没有下载目录",systemImage:"folder.badge.plus",description:Text("下载公众号文章后，会按公众号显示在这里。")).frame(maxWidth:.infinity,maxHeight:.infinity)
   } else {
    ScrollView {
     TimelineView(.periodic(from:.now,by:1)) {timeline in
      LazyVStack(spacing:0) {
       ForEach(library.downloadBatches.filter{!$0.batch_id.isEmpty && ($0.canStop || $0.canceledCount>0)},id:\.batch_id) {batch in
        BatchControlsView(library:library,batch:batch).padding(.horizontal,24).padding(.vertical,8)
       }
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
   Button("在 Finder 打开"){library.openDirectory(folder.url)}.buttonStyle(.bordered).disabled(library.openingDirectory)
  }.padding(.vertical,16).padding(.horizontal,24)
 }
}

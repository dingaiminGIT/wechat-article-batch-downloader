import SwiftUI

struct ArticleDownloadBar: View {
 @ObservedObject var library: Library
 var body: some View {
  VStack(alignment:.leading,spacing:10) {
   if library.queueing {
    HStack {ProgressView().controlSize(.small);Text(library.queueStatus).font(.callout);Spacer();Button("停止添加"){library.stopQueueing()}}
   } else {
    Label(library.scan.status == "running" ? "正在读取列表，不会自动下载。读取完成或暂停后，可开始下载。" : "列表已读取；不会自动下载。点击「开始下载」才会保存正文与图片。",systemImage:"info.circle").font(.callout).foregroundStyle(.secondary)
    HStack(spacing:12) {
     Picker("下载模式",selection:$library.downloadMode) {ForEach(DownloadMode.allCases){mode in Text(mode.title).tag(mode)}}.frame(width:210)
     Spacer(minLength:8)
     Button("下载所选 \(library.selectedArticles.count) 篇…"){library.requestDownload(selectedOnly:true)}.disabled(library.selectedArticles.isEmpty || library.scan.status == "running")
     Button("下载全部 \(library.scan.articles.count) 篇…"){library.requestDownload(selectedOnly:false)}.buttonStyle(.borderedProminent).disabled(library.scan.status == "running")
    }
    Text(library.downloadModeDescription).font(.caption).foregroundStyle(library.downloadMode == .fast ? Color.orange : Color.secondary)
   }
  }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
 }
}

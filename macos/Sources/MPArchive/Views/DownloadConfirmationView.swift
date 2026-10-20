import SwiftUI

struct DownloadConfirmationView:View {
 @ObservedObject var library:Library
 let draft:DownloadDraft
 var body:some View {
  VStack(alignment:.leading,spacing:20) {
   Text("确认批量下载").font(.title2.bold())
   Text("\(draft.account.nickname) · \(draft.articles.count) 篇文章").font(.headline)
   Picker("下载模式",selection:$library.downloadMode) {
    ForEach(DownloadMode.allCases) {mode in Text(mode.title).tag(mode)}
   }.pickerStyle(.segmented)
   Text(library.downloadMode.detail).font(.callout)
   Text("已有文件自动跳过。遇到微信验证会暂停，不会自动重试。\n开始后可在下载中心暂停、继续或终止整个批次；暂停或终止会保留已下载文件。").font(.callout).foregroundStyle(.secondary)
   if !library.canDownloadNative {Label("当前连接尚未就绪，确认后会提示缺少的步骤。",systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(.orange)}
   HStack {
    Spacer()
    Button("取消"){library.downloadDraft=nil}.keyboardShortcut(.cancelAction)
    Button("按\(library.downloadMode == .safe ? "稳妥" : "快速")模式开始下载"){Task{await library.confirmDownload(draft)}}.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
   }
  }.padding(24).frame(width:480)
 }
}

import SwiftUI
struct ArticlesView: View {
 @ObservedObject var library: Library
 @ObservedObject var backend: Backend
 var body: some View {
  VStack(alignment:.leading,spacing:0) {
   VStack(alignment:.leading,spacing:16) {
    HStack{VStack(alignment:.leading,spacing:5){Text(library.account?.nickname ?? "公众号").font(.title2.weight(.semibold));Text(headerDetail).font(.callout).foregroundStyle(.secondary)};Spacer();Button{Task{await library.refresh()}}label:{Image(systemName:"arrow.clockwise")}.help("刷新")}
    HStack(spacing:12) {
     Text("读取范围").font(.callout).foregroundStyle(.secondary)
     Picker("读取范围",selection:$library.options.mode){Text("最近文章").tag("recent");Text("全部历史").tag("all");Text("日期范围").tag("date")}.labelsHidden().pickerStyle(.segmented).frame(width:280)
     if library.options.mode == "recent" {TextField("篇数",value:$library.options.limit,format:.number).frame(width:70);Text("篇").foregroundStyle(.secondary)}
     Spacer()
     if library.scan.status == "running" {Button("暂停读取"){Task{await library.pauseScan()}}}
     else if ["paused","error"].contains(library.scan.status) {
      Button("重新读取列表"){Task{await library.startScan()}}.disabled(library.scanBusy || library.queueing)
      if !library.scan.requiresRestart {Button("继续读取列表"){Task{await library.startScan(resume:true)}}.buttonStyle(.borderedProminent).help("从已保存的进度继续").disabled(library.scanBusy || library.queueing)}
     } else {
      Button(library.scan.articles.isEmpty ? "读取文章列表" : "重新读取列表"){Task{await library.startScan()}}.buttonStyle(.borderedProminent).disabled(library.scanBusy || library.queueing)
     }
    }
    if library.options.mode == "date" {HStack {DatePicker("从",selection:$library.after,displayedComponents:.date);DatePicker("至",selection:$library.before,displayedComponents:.date);Spacer()}.fixedSize(horizontal:true,vertical:false)}
    HStack(spacing:8){if library.scan.status == "running"{ProgressView().controlSize(.small)}else{Image(systemName:library.scan.status == "error" ? "exclamationmark.triangle" : "info.circle")};Text(library.scan.requiresRestart ? "这是旧版列表记录。请重新读取列表，已有文件仍会保留。" : library.scan.message.isEmpty ? "选择范围后读取列表；不会自动下载" : library.scan.message).font(.callout);Spacer()}.foregroundStyle(library.scan.status == "error" ? Color.orange : Color.secondary)
    if !canRead {Text("读取和下载暂不可用，请先完成上方连接步骤。已保存的文件仍可离线查看。").font(.callout).foregroundStyle(.secondary)}
   }.padding(20).fixedSize(horizontal:false,vertical:true)
   if library.hasAccountHistory {HStack(spacing:12){Text(library.hasSavedAccount ? "本机实际文件 \(library.savedAccountCount) 篇" : "有历史任务记录，未找到本地正文文件").font(.callout).foregroundStyle(library.hasSavedAccount ? Color.secondary : Color.orange);Button("打开本地目录"){library.openSavedAccountDirectory()}.disabled(library.openingDirectory);Text("无需连接微信").font(.caption).foregroundStyle(.secondary);Spacer()}.padding(.horizontal,24).padding(.bottom,16)}
   Divider()
   if !library.scan.articles.isEmpty {
    ArticleDownloadBar(library:library).fixedSize(horizontal:false,vertical:true)
    Divider()
   }
   if library.scan.articles.isEmpty && library.hasSavedAccount {
    ContentUnavailableView {
     Label("文章已经保存在本机",systemImage:"folder.fill")
    } description: {
     Text("“\(library.account?.nickname ?? "这个公众号")”已有 \(library.savedAccountCount) 篇。可重新读取历史以检查新增文章。")
    } actions: {
     Button("打开公众号目录"){library.openSavedAccountDirectory()}.buttonStyle(.borderedProminent)
    }.frame(maxWidth:.infinity,maxHeight:.infinity)
   } else if library.scan.articles.isEmpty {
    ContentUnavailableView(emptyTitle,systemImage:"doc.text.magnifyingglass",description:Text(emptyDescription)).frame(maxWidth:.infinity,maxHeight:.infinity)
   } else {
    HStack{Image(systemName:"magnifyingglass").foregroundStyle(.secondary);TextField("搜索标题或摘要",text:$library.query).textFieldStyle(.plain);Text("\(library.visibleArticles.count) 篇").font(.caption).foregroundStyle(.secondary)}.padding(14)
    GeometryReader { tableSpace in
     Table(library.visibleArticles,selection:$library.selectedArticles) {
     TableColumn("文章") {a in VStack(alignment:.leading,spacing:5){Text(a.title).font(.body).lineLimit(1);Text(a.digest.isEmpty ? "公众号文章" : a.digest).font(.caption).foregroundStyle(.secondary).lineLimit(1)}.padding(.vertical,7)}
     TableColumn("发布时间") {a in Text(a.date,format:.dateTime.year().month().day()).font(.callout).foregroundStyle(.secondary)}.width(120)
     }.frame(width:tableSpace.size.width,height:tableSpace.size.height)
     .contextMenu(forSelectionType:String.self){ids in if ids.count == 1,let a = library.scan.articles.first(where:{$0.id == ids.first}){Button("复制文章链接"){library.copyLink(a)}};Button("下载所选文章…"){library.requestDownload(selectedOnly:true)}.disabled(library.selectedArticles.isEmpty || library.queueing || library.scan.status == "running")}
    }.frame(minHeight:80,maxHeight:.infinity).clipped().layoutPriority(-1)
   }
  }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top).navigationTitle(library.account?.nickname ?? "公众号")
 }
 private var canRead: Bool {backend.running && library.canReadNative}
 private var emptyTitle: String {
  if library.scan.status == "running" {return "正在读取文章列表"}
  if ["paused","error"].contains(library.scan.status) {return "读取尚未完成"}
  return "先读取，再选择文章下载"
 }
 private var emptyDescription: String {
  if library.scan.status == "running" {return "正在向微信请求历史列表，读取进度会自动保存。"}
  if ["paused","error"].contains(library.scan.status) {return "当前没有读取结果，不代表公众号没有文章。请查看上方原因，恢复连接后继续读取。"}
  return canRead ? "在微信打开这个公众号的正文和主页，然后点击上方「读取文章」。" : "按上方提示连接微信。完成后，选择读取范围并点击「读取文章」。"
 }
 private var headerDetail:String {
  if library.scan.articles.isEmpty {return library.savedAccountCount > 0 ? "尚未读取 · 本机已保存 \(library.savedAccountCount) 篇" : "尚未读取历史文章"}
  let progress = ["paused","error"].contains(library.scan.status) ? "已读取 \(library.scan.articles.count) 篇 · 可继续" : "本次读取 \(library.scan.articles.count) 篇"
  return progress + (library.savedAccountCount > 0 ? " · 本机已保存 \(library.savedAccountCount) 篇" : "")
 }
}

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
     else {
      if ["paused","error"].contains(library.scan.status){Button("从断点继续"){Task{await library.startScan(resume:true)}}.help("沿用上次读取范围，从保存的页码继续").disabled(!backend.running || library.scanBusy)}
      Button(library.scan.articles.isEmpty ? "读取文章" : "重新读取"){Task{await library.startScan()}}.buttonStyle(.borderedProminent).disabled(!backend.running || library.scanBusy || library.queueing)
     }
    }
    if library.options.mode == "date" {HStack {DatePicker("从",selection:$library.after,displayedComponents:.date);DatePicker("至",selection:$library.before,displayedComponents:.date);Spacer()}.fixedSize(horizontal:true,vertical:false)}
    HStack(spacing:8){if library.scan.status == "running"{ProgressView().controlSize(.small)}else{Image(systemName:library.scan.status == "error" ? "exclamationmark.triangle" : "info.circle")};Text(library.scan.message.isEmpty ? "选择范围后读取文章" : library.scan.message).font(.callout);Spacer()}.foregroundStyle(library.scan.status == "error" ? Color.orange : Color.secondary)
    if !backend.connected {HStack{Text("可尝试使用已有连接读取；若失效，请连接微信后重新打开文章").font(.callout).foregroundStyle(.secondary);Spacer();Button(backend.needsAuthorization ? "信任并连接" : "连接微信"){Task{await backend.connect(authorize:backend.needsAuthorization)}}.disabled(backend.busy)}}
    if backend.needsAuthorization {Text(backend.message).font(.callout).foregroundStyle(.orange).textSelection(.enabled)}
   }.padding(24)
   if !library.scan.articles.isEmpty && library.hasSavedAccount {HStack{Text("本机已有 \(library.savedAccountCount) 篇").font(.callout);Spacer();Button("打开公众号目录"){library.openSavedAccountDirectory()}}.padding(.horizontal,24).padding(.bottom,16)}
   Divider()
   if library.scan.articles.isEmpty && library.hasSavedAccount {
    ContentUnavailableView {
     Label("文章已经保存在本机",systemImage:"folder.fill")
    } description: {
     Text("“\(library.account?.nickname ?? "这个公众号")”已有 \(library.savedAccountCount) 篇。可重新读取历史以检查新增文章。")
    } actions: {
     Button("打开公众号目录"){library.openSavedAccountDirectory()}.buttonStyle(.borderedProminent)
    }.frame(maxWidth:.infinity,maxHeight:.infinity)
   } else if library.scan.articles.isEmpty {
    ContentUnavailableView("文章会出现在这里",systemImage:"doc.text.magnifyingglass",description:Text("先在微信打开这个公众号的文章，再点击“读取文章”。")).frame(maxWidth:.infinity,maxHeight:.infinity)
   } else {
    HStack{Image(systemName:"magnifyingglass").foregroundStyle(.secondary);TextField("搜索标题或摘要",text:$library.query).textFieldStyle(.plain);Text("\(library.visibleArticles.count) 篇").font(.caption).foregroundStyle(.secondary)}.padding(14)
    Table(library.visibleArticles,selection:$library.selectedArticles) {
     TableColumn("文章") {a in VStack(alignment:.leading,spacing:5){Text(a.title).font(.body).lineLimit(1);Text(a.digest.isEmpty ? "公众号文章" : a.digest).font(.caption).foregroundStyle(.secondary).lineLimit(1)}.padding(.vertical,7)}
     TableColumn("发布时间") {a in Text(a.date,format:.dateTime.year().month().day()).font(.callout).foregroundStyle(.secondary)}.width(120)
    }.contextMenu(forSelectionType:String.self){ids in if ids.count == 1,let a = library.scan.articles.first(where:{$0.id == ids.first}){Button("复制文章链接"){library.copyLink(a)}};Button("下载所选文章"){Task{await library.enqueue(selectedOnly:true)}}.disabled(library.selectedArticles.isEmpty)}
   }
   if !library.scan.articles.isEmpty {Divider()
   HStack(alignment:.center) {
    VStack(alignment:.leading,spacing:5) {
     Picker("下载速度",selection:$library.downloadMode){Text("安全").tag("safe");Text("快速").tag("fast")}.pickerStyle(.segmented).frame(width:170)
     Text(library.downloadModeDescription).font(.caption).foregroundStyle(library.downloadMode == "fast" ? Color.orange : Color.secondary)
    }
    Text(library.selectedArticles.isEmpty ? "选择文章，或下载全部读取结果" : "已选择 \(library.selectedArticles.count) 篇").font(.callout).foregroundStyle(.secondary)
    Spacer()
    if library.queueing {ProgressView().controlSize(.small);Button("停止添加"){library.stopQueueing()}}
    else {
     Button("下载所选"){Task{await library.enqueue(selectedOnly:true)}}.disabled(library.selectedArticles.isEmpty || !backend.running)
     Button("下载全部 \(library.scan.articles.count) 篇"){Task{await library.enqueue(selectedOnly:false)}}.buttonStyle(.borderedProminent).disabled(library.scan.articles.isEmpty || !backend.running || library.scan.status == "running")
    }
   }.padding(16)}
  }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top).navigationTitle(library.account?.nickname ?? "公众号")
 }
 private var headerDetail:String {
  if library.scan.articles.isEmpty {return library.savedAccountCount > 0 ? "尚未读取 · 本机已保存 \(library.savedAccountCount) 篇" : "尚未读取历史文章"}
  return "本次读取 \(library.scan.articles.count) 篇" + (library.savedAccountCount > 0 ? " · 本机已保存 \(library.savedAccountCount) 篇" : "")
 }
}

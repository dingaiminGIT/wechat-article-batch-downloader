import SwiftUI
import AppKit

struct ContentView: View {
 @ObservedObject var backend: Backend
 @ObservedObject var library: Library
 var body: some View {
  NavigationSplitView {
   List(selection: $library.selected) {
    Section {
     Label("开始归档",systemImage:"books.vertical").tag("welcome")
     Label("下载中心",systemImage:"arrow.down.circle").tag("downloads")
    }
    Section("公众号 · \(library.accounts.count)") {
     ForEach(library.accounts) {account in
      HStack(spacing:10) {
       Image(systemName:"text.bubble").foregroundStyle(.tint)
       VStack(alignment:.leading,spacing:3){Text(account.nickname).lineLimit(1);Text(library.accountConnectionLabel(account.biz)).font(.caption).foregroundStyle(.secondary)}
      }.padding(.vertical,3).tag(account.biz)
     }
    }
   }.listStyle(.sidebar)
    .navigationSplitViewColumnWidth(min:210,ideal:240,max:300)
    .safeAreaInset(edge:.bottom) {
     VStack(alignment:.leading,spacing:8) {
      Label(library.nativeConnection.ready ? "原生读取已连接" : "本地文章库",systemImage:library.nativeConnection.ready ? "checkmark.circle.fill" : "internaldrive").font(.caption).foregroundStyle(library.nativeConnection.ready ? .green : .secondary)
      SettingsLink {Label("设置与连接",systemImage:"gearshape")}.buttonStyle(.plain).font(.caption)
     }.frame(maxWidth:.infinity,alignment:.leading).padding(16)
    }
  } detail: {
   // Bound the AppKit-hosted detail's ideal size. Without this boundary, Table
   // can enlarge the entire split view beyond the window and hide both rails.
   GeometryReader { detailSpace in
   VStack(spacing:0) {
    if backend.running {NativeConnectionBar(library:library)}
    if !backend.running || backend.busy {
     HStack {if backend.busy {ProgressView().controlSize(.small)};Text(backend.message).font(.callout);Spacer();if !backend.busy {Button("启动服务"){Task{await backend.launch()}}}}.padding().background(.quaternary)
    }
    if !library.message.isEmpty {
     Divider()
     HStack {Image(systemName:"info.circle").foregroundStyle(.secondary);Text(library.message).font(.callout).textSelection(.enabled);Spacer();Button{library.message = ""}label:{Image(systemName:"xmark")}.buttonStyle(.plain)}.padding(12)
    }
    if library.selected == "downloads" {DownloadsView(library: library, backend: backend)}
    else if library.account != nil {ArticlesView(library: library, backend: backend)}
    else {WelcomeView(backend: backend, library: library)}
   }.frame(width:detailSpace.size.width,height:detailSpace.size.height,alignment:.top)
   }
  }
  .tint(Color(red:0.12,green:0.48,blue:0.34))
  .onChange(of:library.selected){_,_ in Task{await library.selectionChanged()}}
  .sheet(item:$library.downloadDraft) {draft in DownloadConfirmationView(library:library,draft:draft)}
  .confirmationDialog("终止这个批次？",isPresented:Binding(get:{library.stopBatchConfirmation != nil},set:{if !$0 {library.stopBatchConfirmation=nil}}),titleVisibility:.visible) {
   Button("终止批次，保留文件",role:.destructive) {if let batch=library.stopBatchConfirmation {library.stopBatchConfirmation=nil;Task{await library.controlBatch(batch,action:"stop")}}}
   Button("返回",role:.cancel){library.stopBatchConfirmation=nil}
  } message: {Text("停止后续文章，当前正在导出的文章完成后停止。已下载文件不会删除；此批次不能继续，需要时可重新选择文章下载。")}
  .alert(library.notice?.title ?? "操作提示",isPresented:Binding(get:{library.notice != nil},set:{if !$0 {library.notice = nil}})) {
   Button("知道了",role:.cancel){library.notice = nil}
  } message: {Text(library.notice?.message ?? "")}
 }
}
struct WelcomeView: View {
 @ObservedObject var backend: Backend
 @ObservedObject var library: Library
 var body: some View {
  ScrollView {
   VStack(alignment:.leading,spacing:28) {
    HStack(alignment:.top){
     VStack(alignment:.leading,spacing:12){Text("把值得留下的文章，\n收进自己的书架。").font(.system(size:32,weight:.semibold)).lineSpacing(5);Text("公众号历史文章 · 本地保存 · 随时阅读").foregroundStyle(.secondary)}
     Spacer();Image(systemName:"books.vertical.fill").font(.system(size:70)).foregroundStyle(.tint).padding(12)
    }.padding(.top,20)
    HStack(spacing:12){Label("Markdown",systemImage:"doc.text");Label("纯文本",systemImage:"text.alignleft");Label("HTML 与图片",systemImage:"photo.on.rectangle");Label("JSONL 语料",systemImage:"curlybraces")}.font(.caption).foregroundStyle(.secondary)
    Divider()
    VStack(alignment:.leading,spacing:24) {
     step("1",title:library.nativeConnection.channelConnected ? "微信通道已连接" : "连接微信",detail:"点击这里的连接按钮，再到微信「发现 → 小程序」打开腾讯文档，停在首页即可。无需打开文档；请保留小程序窗口。") {
      if library.nativeConnection.channelConnected {Label("已完成",systemImage:"checkmark.circle.fill").font(.callout).foregroundStyle(.green)}
      else {NativeConnectionActions(library:library).disabled(!backend.running);Text("若一直等待：关闭小程序，再重新打开首页。").font(.caption).foregroundStyle(.secondary)}
     }
     step("2",title:"打开公众号主页，确认识别结果",detail:"在微信正文里点击蓝色公众号名称，进入该账号的主页；只停留在推荐流或右侧正文面板，可能无法识别。以下出现目标账号才表示识别成功，通道连接成功不等于该账号已识别。不需要是自己运营的公众号。") {
      Button("打开微信"){NSWorkspace.shared.open(URL(fileURLWithPath:"/Applications/WeChat.app"))}.buttonStyle(.bordered)
      if let recognized = library.nativeConnection.accounts, !recognized.isEmpty {
       Text("本次已识别（点击进入）：").font(.caption).foregroundStyle(.secondary)
       ForEach(recognized,id:\.biz) {account in
        Button(account.nickname){library.selected = account.biz}.buttonStyle(.bordered)
       }
      } else {Text("尚未识别到公众号；打开主页后等待几秒。").font(.callout).foregroundStyle(.secondary)}
     }
     step("3",title:"先读取列表，再批量下载",detail:"选中左侧公众号，选择最近文章、全部历史或日期范围。读取后下载全部或所选文章；支持暂停、继续和跳过已有文件。") {
      Button("打开导出目录（无需微信连接）"){library.openDirectory(backend.downloads)}.buttonStyle(.bordered).disabled(library.openingDirectory)
     }
    }
    DisclosureGroup("连接与使用提醒") {
     VStack(alignment:.leading,spacing:8) {
      Text("微信退出重启后，需要重新连接，再打开小程序首页。小程序提前打开时，关闭后重开即可。")
      Text("遇到微信验证时会暂停下载。请在微信手动完成验证，打开目标公众号正文后再重试。")
      Text("原生模式不需要开启旧版代理或信任新证书。本机体验版适配已准备环境的微信 4.1.13，微信升级后需要重新验证兼容性。")
     }.font(.callout).foregroundStyle(.secondary).padding(.top,8)
    }
    if !library.accounts.isEmpty {Button("查看已保存公众号"){library.selected = library.accounts.first?.biz}.buttonStyle(.bordered)}
    Spacer(minLength:20)
   }.padding(36).frame(maxWidth:950,alignment:.leading)
  }.navigationTitle("开始归档")
 }
 func step<Content:View>(_ n:String,title:String,detail:String,@ViewBuilder action:()->Content)->some View {
  HStack(alignment:.top,spacing:16){Text(n).font(.title3.weight(.semibold)).foregroundStyle(.tint).frame(width:36,height:36).background(.tint.opacity(0.08),in:Circle());VStack(alignment:.leading,spacing:8){Text(title).font(.headline);Text(detail).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true);action().padding(.top,3)}}
 }
}

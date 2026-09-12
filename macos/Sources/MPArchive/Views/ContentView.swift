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
       VStack(alignment:.leading,spacing:3){Text(account.nickname).lineLimit(1);Text(account.is_effective ? "最近已连接" : "打开文章以更新连接").font(.caption).foregroundStyle(.secondary)}
      }.padding(.vertical,3).tag(account.biz)
     }
    }
   }.listStyle(.sidebar)
    .navigationSplitViewColumnWidth(min:210,ideal:240,max:300)
    .safeAreaInset(edge:.bottom) {
     VStack(alignment:.leading,spacing:8) {
      Label(backend.connected ? "微信连接已启用" : "本地文章库",systemImage:backend.connected ? "checkmark.circle.fill" : "internaldrive").font(.caption).foregroundStyle(backend.connected ? .green : .secondary)
      SettingsLink {Label("设置与连接",systemImage:"gearshape")}.buttonStyle(.plain).font(.caption)
     }.frame(maxWidth:.infinity,alignment:.leading).padding(16)
    }
  } detail: {
   VStack(spacing:0) {
    if !backend.running || backend.busy {
     HStack {if backend.busy {ProgressView().controlSize(.small)};Text(backend.message).font(.callout);Spacer();if !backend.busy {Button("启动服务"){Task{await backend.launch()}}}}.padding().background(.quaternary)
    }
    if library.selected == "downloads" {DownloadsView(library: library, backend: backend)}
    else if library.account != nil {ArticlesView(library: library, backend: backend)}
    else {WelcomeView(backend: backend, library: library)}
    if !library.message.isEmpty {
     Divider()
     HStack {Image(systemName:"info.circle").foregroundStyle(.secondary);Text(library.message).font(.callout).textSelection(.enabled);Spacer();Button{library.message = ""}label:{Image(systemName:"xmark")}.buttonStyle(.plain)}.padding(12)
    }
   }
  }
  .tint(Color(red:0.12,green:0.48,blue:0.34))
  .onChange(of:library.selected){_,_ in Task{await library.selectionChanged()}}
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
     step("1",title:"连接电脑微信",detail:"首次连接由 macOS 授权一次；以后连接无需重复输入密码。连接期间保持应用运行。") {
      Button(backend.connected ? "已连接微信" : backend.needsAuthorization ? "授权并连接" : "连接微信") {Task{await backend.connect(authorize:backend.needsAuthorization)}}.buttonStyle(.borderedProminent).disabled(backend.busy || backend.connected || !backend.running)
     }
     step("2",title:"打开目标公众号的一篇文章",detail:"在微信里打开你想归档的公众号文章，识别后会出现在左侧。无需管理该公众号。") {
      Button("打开微信"){NSWorkspace.shared.open(URL(fileURLWithPath:"/Applications/WeChat.app"))}.buttonStyle(.bordered)
     }
     step("3",title:"选择范围，开始归档",detail:"选中左侧公众号，读取历史后下载。支持暂停读取、断点继续和跳过已有文章。") {
      Button("打开导出目录"){NSWorkspace.shared.open(backend.downloads)}.buttonStyle(.bordered)
     }
    }
    Text(backend.message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
    if !library.accounts.isEmpty {Button("查看已识别公众号"){library.selected = library.accounts.first?.biz}.buttonStyle(.bordered)}
    Spacer(minLength:20)
   }.padding(36).frame(maxWidth:950,alignment:.leading)
  }.navigationTitle("开始归档")
 }
 func step<Content:View>(_ n:String,title:String,detail:String,@ViewBuilder action:()->Content)->some View {
  HStack(alignment:.top,spacing:16){Text(n).font(.title3.weight(.semibold)).foregroundStyle(.tint).frame(width:36,height:36).background(.tint.opacity(0.08),in:Circle());VStack(alignment:.leading,spacing:8){Text(title).font(.headline);Text(detail).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true);action().padding(.top,3)}}
 }
}

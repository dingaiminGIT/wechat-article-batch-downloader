import SwiftUI
import AppKit
struct SettingsView: View {
 @ObservedObject var backend: Backend
 @ObservedObject var library: Library
 @State private var chosenDirectory = UserDefaults.standard.string(forKey:"downloadDirectory") ?? ""
 @State private var zipMessage = ""
 @State private var zipping = false
 var body: some View {
  Form {
   Section("微信连接") {
    Text(backend.message).foregroundStyle(.secondary).textSelection(.enabled)
    HStack {
     Button(backend.connected ? "断开微信连接" : backend.needsAuthorization ? "信任并连接" : "连接微信") {Task{if backend.connected{await backend.launch()}else{await backend.connect(authorize:backend.needsAuthorization)}}}.disabled(backend.busy || !backend.running)
     Button("恢复网络配置"){Task{await backend.recover()}}.disabled(backend.busy)
    }
    Text("连接期间使用本机代理读取微信文章；断开或退出会恢复连接前的代理配置。证书只在首次连接时加入当前用户的信任列表，退出应用不会删除证书。").font(.caption).foregroundStyle(.secondary)
   }
   Section("导出位置") {
    Text(chosenDirectory.isEmpty ? backend.downloads.path : chosenDirectory).font(.callout).textSelection(.enabled)
    HStack{Button("选择目录"){
     let panel = NSOpenPanel();panel.canChooseDirectories = true;panel.canChooseFiles = false;panel.canCreateDirectories = true;panel.allowsMultipleSelection = false
     if panel.runModal() == .OK,let url = panel.url {chosenDirectory = url.path;UserDefaults.standard.set(url.path,forKey:"downloadDirectory")}
    };Button("打开当前目录"){NSWorkspace.shared.open(backend.downloads)}}
    Text("更换目录后，退出并重新打开应用生效。已有文件保留在原目录。").font(.caption).foregroundStyle(.secondary)
    HStack{Button("将当前导出目录打包为 ZIP") {exportZIP()}.disabled(zipping);if zipping{ProgressView().controlSize(.small)}}
    if !zipMessage.isEmpty {Text(zipMessage).font(.caption).foregroundStyle(.secondary)}
   }
   Section("默认下载速度") {
    Picker("模式",selection:$library.downloadMode){Text("安全").tag("safe");Text("快速").tag("fast")}.pickerStyle(.segmented)
    Text(library.downloadModeDescription).font(.caption).foregroundStyle(library.downloadMode == "fast" ? Color.orange : Color.secondary)
   }
   Section("应用与诊断") {
    Text("公众号文章下载器 \(appVersion) · \(buildChannel)")
    Button("打开诊断目录"){NSWorkspace.shared.open(backend.dataDirectory)}
    Text("历史读取状态和下载目录信息保存在本机。关闭窗口会继续运行；退出应用会结束连接，未完成的历史读取可在下次继续。").font(.caption).foregroundStyle(.secondary)
   }
  }.formStyle(.grouped).padding(12)
 }
 private var appVersion: String {Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "开发版"}
 private var buildChannel: String {Bundle.main.object(forInfoDictionaryKey:"MPArchiveChannel") as? String ?? "本机运行"}
 private func exportZIP() {
  let panel = NSSavePanel();panel.nameFieldStringValue = "公众号文章归档.zip";panel.allowedContentTypes = [.zip]
  guard panel.runModal() == .OK,let url = panel.url else{return}
  if url.path.hasPrefix(backend.downloads.path+"/"){zipMessage = "请将 ZIP 保存到导出目录之外";return}
  zipping = true;zipMessage = "正在打包"
  Task{do{let result = try await Backend.run("/usr/bin/ditto",["-c","-k","--sequesterRsrc","--keepParent",backend.downloads.path,url.path]);zipMessage = result.0 == 0 ? "已保存：\(url.lastPathComponent)" : "打包失败，请检查目录权限";if result.0 == 0{NSWorkspace.shared.activateFileViewerSelecting([url])}}catch{zipMessage = error.localizedDescription};zipping = false}
 }
}

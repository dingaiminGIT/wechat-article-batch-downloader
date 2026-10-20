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
   Section("原生微信连接") {
    Text(library.nativeConnection.title).font(.headline)
    Text(library.nativeConnection.guidance).foregroundStyle(.secondary).textSelection(.enabled)
    HStack {
     Button(library.nativeConnection.needsReconnect ? "连接微信" : "检查状态") {Task{if library.nativeConnection.needsReconnect {await library.connectNative()}else{await library.refreshNativeStatus()}}}.disabled(library.nativeBusy || !backend.running)
     Button("断开连接"){Task{await library.disconnectNative()}}.disabled(library.nativeBusy || library.nativeConnection.state == "stopped")
    }
    Text("先连接，再打开腾讯文档小程序首页，无需点进文档。本机体验版适配已准备环境的微信 4.1.13；不启用旧版代理、不新增证书。").font(.caption).foregroundStyle(.secondary)
   }
   Section("导出位置") {
    Text(chosenDirectory.isEmpty ? backend.downloads.path : chosenDirectory).font(.callout).textSelection(.enabled)
    HStack{Button("选择目录"){
     let panel = NSOpenPanel();panel.canChooseDirectories = true;panel.canChooseFiles = false;panel.canCreateDirectories = true;panel.allowsMultipleSelection = false
     if panel.runModal() == .OK,let url = panel.url {chosenDirectory = url.path;UserDefaults.standard.set(url.path,forKey:"downloadDirectory")}
    };Button("打开当前目录"){library.openDirectory(backend.downloads)}.disabled(library.openingDirectory)}
    Text("更换目录后，退出并重新打开应用生效。已有文件保留在原目录。").font(.caption).foregroundStyle(.secondary)
    HStack{Button("将当前导出目录打包为 ZIP") {exportZIP()}.disabled(zipping);if zipping{ProgressView().controlSize(.small)}}
    if !zipMessage.isEmpty {Text(zipMessage).font(.caption).foregroundStyle(.secondary)}
   }
   Section("下载策略") {
    Picker("新下载任务",selection:$library.downloadMode){ForEach(DownloadMode.allCases){mode in Text(mode.title).tag(mode)}}.pickerStyle(.segmented)
    Text("已有文件自动跳过；速度设置只影响之后创建的任务。").font(.caption).foregroundStyle(.secondary)
    Text(library.downloadModeDescription).font(.caption).foregroundStyle(.secondary)
   }
   Section("应用与诊断") {
    Text("公众号文章下载器 \(appVersion) · \(buildChannel)")
    Button("打开诊断目录"){NSWorkspace.shared.open(backend.dataDirectory)}
    Text("历史读取状态和下载目录信息保存在本机。关闭窗口会继续运行；退出应用会结束连接，未完成的历史读取可在下次继续。").font(.caption).foregroundStyle(.secondary)
    Button("查看实现原理与使用说明") {if let url = Bundle.main.url(forResource:"实现原理与使用说明",withExtension:"md"){NSWorkspace.shared.open(url)}}
    DisclosureGroup("旧版网络恢复（仅排障）") {
     Text("仅用于清理旧版工具遗留的代理。此操作会停止本地服务，不用于建立原生连接，不会删除证书或下载文件。").font(.caption).foregroundStyle(.secondary)
     Button("停止服务并恢复旧版网络配置"){Task{await library.disconnectNative();await backend.recover()}}.disabled(backend.busy || library.nativeBusy)
    }
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

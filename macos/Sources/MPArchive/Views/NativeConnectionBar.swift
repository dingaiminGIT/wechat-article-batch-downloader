import SwiftUI
import AppKit

struct NativeConnectionBar: View {
 @ObservedObject var library: Library
 var body: some View {
  HStack(alignment:.center,spacing:12) {
   if library.nativeBusy {ProgressView().controlSize(.small)}
   else {Image(systemName:library.nativeConnection.channelConnected ? "checkmark.circle.fill" : "link").font(.title3).foregroundStyle(library.nativeConnection.channelConnected ? Color.green : Color.secondary)}
   VStack(alignment:.leading,spacing:8) {
    Text(library.nativeBusy ? "正在连接微信…" : library.nativeConnection.title).font(.headline)
    Text(library.nativeBusy ? "请稍候，连接组件就绪后再打开小程序首页。" : library.nativeConnection.guidance)
     .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
    if library.selected != "welcome" {NativeConnectionActions(library:library)}
   }.frame(maxWidth:.infinity,alignment:.leading)
   if library.selected != "welcome" {Button("操作指引"){library.selected = "welcome"}.buttonStyle(.borderless)}
  }.padding(16).background(.quaternary)
 }
}
struct NativeConnectionActions: View {
 @ObservedObject var library: Library
 var body: some View {
  HStack(spacing:12) {
   if library.nativeConnection.needsReconnect {
    Button(library.nativeConnection.state == "stopped" ? "连接微信" : "重新连接微信") {Task{await library.connectNative()}}
     .buttonStyle(.borderedProminent).disabled(library.nativeBusy)
   } else if !library.nativeConnection.canDownload {
    Button("打开微信") {NSWorkspace.shared.open(URL(fileURLWithPath:"/Applications/WeChat.app"))}.buttonStyle(.borderedProminent)
    Button("检查连接状态") {Task{await library.refreshNativeStatus()}}.disabled(library.nativeBusy)
   }
  }
 }
}

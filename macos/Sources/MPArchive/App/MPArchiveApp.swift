import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
 static weak var backend: Backend?
 private var ending = false
 func applicationDidFinishLaunching(_ notification: Notification) {
  NSApp.setActivationPolicy(.regular)
  NSApp.activate(ignoringOtherApps: true)
 }
 func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
  if ending {return .terminateNow};ending = true
  Task {await Self.backend?.stop();sender.reply(toApplicationShouldTerminate: true)}
  return .terminateLater
 }
 func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {false}
}
@main struct MPArchiveApp: App {
 @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
 @StateObject private var backend = Backend()
 @StateObject private var library = Library()
 var body: some Scene {
  WindowGroup("公众号文章下载器", id: "main") {
   GeometryReader { geometry in
    ContentView(backend: backend, library: library)
     .frame(width:geometry.size.width,height:geometry.size.height)
     .background(WindowLayoutProbe(selection:library.selected))
   }
    .frame(minWidth: 960, minHeight: 640)
    .task {AppDelegate.backend = backend;if !backend.running && !backend.busy {await backend.launch()};library.begin(backend)}
  }.defaultSize(width: 1180, height: 780)
   .windowStyle(.titleBar)
   .windowToolbarStyle(.expanded)
   .commands {
    CommandGroup(replacing: .newItem) {}
    CommandMenu("文章库") {
     Button("刷新公众号") {Task{await library.refresh()}}.keyboardShortcut("r")
     Button("连接微信") {Task{await library.connectNative()}}.disabled(library.nativeBusy || !backend.running)
     Button("操作指引") {library.selected = "welcome"}
     Button("下载所选文章…") {library.requestDownload(selectedOnly:true)}.keyboardShortcut("d").disabled(library.selectedArticles.isEmpty || library.queueing)
     Button("打开导出目录") {library.openDirectory(backend.downloads)}.keyboardShortcut("o",modifiers:[.command,.shift])
    }
   }
  Settings {SettingsView(backend: backend,library:library).frame(width: 540)}
 }
}

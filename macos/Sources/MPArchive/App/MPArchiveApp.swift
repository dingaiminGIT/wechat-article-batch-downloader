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
   ContentView(backend: backend, library: library)
    .frame(minWidth: 960, minHeight: 640)
    .task {AppDelegate.backend = backend;if !backend.running && !backend.busy {await backend.launch()};library.begin(backend)}
  }.defaultSize(width: 1180, height: 780)
   .commands {
    CommandGroup(replacing: .newItem) {}
    CommandMenu("文章库") {
     Button("刷新公众号") {Task{await library.refresh()}}.keyboardShortcut("r")
     Button("下载所选文章") {Task{await library.enqueue(selectedOnly: true)}}.keyboardShortcut("d").disabled(library.selectedArticles.isEmpty)
     Button("打开导出目录") {NSWorkspace.shared.open(backend.downloads)}.keyboardShortcut("o",modifiers:[.command,.shift])
    }
   }
  Settings {SettingsView(backend: backend,library:library).frame(width: 540)}
 }
}

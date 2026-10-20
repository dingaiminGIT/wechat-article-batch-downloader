import AppKit
import SwiftUI
import OSLog

struct WindowLayoutProbe: NSViewRepresentable {
 var selection:String?
 func makeNSView(context:Context)->ProbeView {ProbeView()}
 func updateNSView(_ view:ProbeView,context:Context) {view.reportSoon()}
 final class ProbeView:NSView {
  private var pending = false
  override func viewDidMoveToWindow() {super.viewDidMoveToWindow();reportSoon()}
  func reportSoon() {
   guard !pending else{return};pending = true
   DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {[weak self] in
    guard let self else{return};self.pending = false
    guard let w = self.window,let content = w.contentView else{return}
    let logger = Logger(subsystem:"com.baiyalab.mp-article-downloader",category:"WindowLayout")
    var splitHeight:CGFloat = 0
    func inspect(_ v:NSView) {
     if v is NSSplitView {splitHeight = max(splitHeight,v.bounds.height)}
     for sub in v.subviews {inspect(sub)}
    }
    inspect(content)
    // Geometry only: never log account identity, article text or session data.
    let overflow = splitHeight > content.bounds.height + 1
    logger.notice("contentHeight=\(content.bounds.height,privacy:.public) splitHeight=\(splitHeight,privacy:.public) overflow=\(overflow,privacy:.public)")
   }
  }
 }
}

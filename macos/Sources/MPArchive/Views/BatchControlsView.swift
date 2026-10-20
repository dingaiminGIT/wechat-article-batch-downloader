import SwiftUI

struct BatchControlsView:View {
 @ObservedObject var library:Library
 let batch:DownloadBatchProgress
 var body:some View {
  VStack(alignment:.leading,spacing:10) {
   HStack {
    Text(URL(fileURLWithPath:batch.path).lastPathComponent).font(.headline)
    Text(batch.modeText ?? "下载批次").font(.caption).foregroundStyle(.secondary)
    Spacer()
    if batch.isActive && batch.canceledCount == 0 {Button("暂停下载"){Task{await library.controlBatch(batch,action:"pause")}}}
    if batch.canResume {Button(batch.failed>0 ? "继续 / 重试" : "继续下载"){Task{await library.controlBatch(batch,action:"resume")}}}
    if batch.canStop {Button("终止下载…"){library.stopBatchConfirmation=batch}.foregroundStyle(.red)}
    if library.controllingBatch==batch.batch_id {ProgressView().controlSize(.small)}
   }
   Text("完成 \(batch.completed) · 下载中 \(batch.running) · 排队 \(batch.queued) · 暂停 \(batch.paused) · 失败 \(batch.failed) · 已终止 \(batch.canceledCount)").font(.caption).monospacedDigit()
   if batch.canceledCount>0 {Text(batch.isActive ? "正在终止：当前文章导出后停止，已保存文件保留。" : "本批次已终止，已保存文件保留。").font(.caption).foregroundStyle(.secondary)}
   else if batch.paused>0 {Text(batch.running>0 ? "正在暂停：当前文章导出完成后暂停，可随时继续。" : "本批次已暂停，点击「继续下载」接着下载。").font(.caption).foregroundStyle(.secondary)}
   else {Text("暂停或终止只影响本批次；当前文章会导出完成，不强行中断文件写入。").font(.caption).foregroundStyle(.secondary)}
  }.padding(16).background(.quaternary,in:RoundedRectangle(cornerRadius:10)).disabled(library.controllingBatch != nil)
 }
}

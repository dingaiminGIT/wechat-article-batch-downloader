import AppKit
let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath:output,withIntermediateDirectories:true)
for size in [16,32,128,256,512] {
 for scale in [1,2] {
  let px = size * scale
  let image = NSImage(size:NSSize(width:px,height:px))
  image.lockFocus()
  let transform = NSAffineTransform();transform.scale(by:CGFloat(px)/1024);transform.concat()
  let rect = NSRect(x:72,y:72,width:880,height:880)
  let bg = NSBezierPath(roundedRect:rect,xRadius:195,yRadius:195)
  NSGradient(starting:NSColor(calibratedRed:0.13,green:0.54,blue:0.38,alpha:1),ending:NSColor(calibratedRed:0.06,green:0.29,blue:0.23,alpha:1))!.draw(in:bg,angle:90)
  NSColor(calibratedWhite:0.97,alpha:1).setFill()
  NSBezierPath(roundedRect:NSRect(x:260,y:265,width:380,height:505),xRadius:32,yRadius:32).fill()
  NSColor(calibratedRed:0.72,green:0.88,blue:0.79,alpha:1).setFill()
  NSBezierPath(roundedRect:NSRect(x:235,y:235,width:380,height:505),xRadius:32,yRadius:32).fill()
  NSColor(calibratedWhite:0.98,alpha:1).setFill()
  NSBezierPath(roundedRect:NSRect(x:215,y:205,width:380,height:505),xRadius:32,yRadius:32).fill()
  NSColor(calibratedRed:0.18,green:0.47,blue:0.35,alpha:1).setFill()
  for y in [590,505,420] {NSBezierPath(roundedRect:NSRect(x:282,y:y,width:235,height:20),xRadius:10,yRadius:10).fill()}
  NSColor(calibratedRed:0.79,green:0.94,blue:0.64,alpha:1).setFill()
  NSBezierPath(roundedRect:NSRect(x:550,y:175,width:255,height:255),xRadius:80,yRadius:80).fill()
  let arrow = NSBezierPath();arrow.move(to:NSPoint(x:677,y:365));arrow.line(to:NSPoint(x:677,y:245));arrow.move(to:NSPoint(x:622,y:292));arrow.line(to:NSPoint(x:677,y:237));arrow.line(to:NSPoint(x:732,y:292));arrow.lineWidth=24;arrow.lineCapStyle = .round;arrow.lineJoinStyle = .round
  NSColor(calibratedRed:0.10,green:0.34,blue:0.25,alpha:1).setStroke();arrow.stroke()
  image.unlockFocus()
  let rep = NSBitmapImageRep(data:image.tiffRepresentation!)!
  let suffix = scale == 2 ? "@2x" : ""
  try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:output+"/icon_\(size)x\(size)\(suffix).png"))
 }
}

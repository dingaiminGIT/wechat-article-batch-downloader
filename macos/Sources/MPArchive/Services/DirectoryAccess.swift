import Foundation

enum DirectoryAccess {
 static func firstExisting(_ candidates:[URL]) -> URL? {
  candidates.first {url in
   var isDirectory: ObjCBool = false
   return FileManager.default.fileExists(atPath:url.path,isDirectory:&isDirectory) && isDirectory.boolValue
  }
 }
}

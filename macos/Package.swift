// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "MPArchive", platforms: [.macOS(.v14)], products: [.executable(name: "MPArchive", targets: ["MPArchive"])], targets: [.executableTarget(name: "MPArchive"), .testTarget(name: "MPArchiveTests", dependencies: ["MPArchive"])])

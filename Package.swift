// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NewsLingo",
    platforms: [.macOS(.v15)],
    targets: [.executableTarget(name: "NewsLingo")],
    swiftLanguageModes: [.v5]
)

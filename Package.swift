// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacCare",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MacCare", targets: ["MacCare"])],
    targets: [.executableTarget(name: "MacCare", path: "Sources/MacCare", resources: [.process("Resources")])]
)

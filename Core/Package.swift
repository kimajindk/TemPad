// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "TemPadCore", platforms: [.macOS(.v13), .iOS(.v17)], products: [.library(name: "TemPadCore", targets: ["TemPadCore"])], targets: [.target(name: "TemPadCore"), .testTarget(name: "TemPadCoreTests", dependencies: ["TemPadCore"])])

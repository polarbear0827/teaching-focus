// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "TeachingFocus", platforms: [.macOS(.v13)], products: [.executable(name: "TeachingFocus", targets: ["TeachingFocus"]), .executable(name: "CoreChecks", targets: ["CoreChecks"])], targets: [.target(name: "FocusCore"), .executableTarget(name: "TeachingFocus", dependencies: ["FocusCore"]), .executableTarget(name: "CoreChecks", dependencies: ["FocusCore"])])

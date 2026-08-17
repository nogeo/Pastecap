// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pastecap",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Pastecap", targets: ["Pastecap"])],
    targets: [.executableTarget(name: "Pastecap", path: "Sources/Pastecap")]
)

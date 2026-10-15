// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AssemblerToy",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "AssemblerCore", targets: ["AssemblerCore"])],
    targets: [
        .target(name: "AssemblerCore"),
        .testTarget(name: "AssemblerCoreTests", dependencies: ["AssemblerCore"])
    ]
)

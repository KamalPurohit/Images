// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AtherKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AtherKit", targets: ["AtherKit"]),
    ],
    targets: [
        .target(name: "AtherKit"),
        .testTarget(name: "AtherKitTests", dependencies: ["AtherKit"]),
    ]
)

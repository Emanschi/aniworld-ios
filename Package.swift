// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AniworldKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AniworldKit", targets: ["AniworldKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
    ],
    targets: [
        .target(
            name: "AniworldKit",
            dependencies: ["SwiftSoup"]
        ),
        .testTarget(
            name: "AniworldKitTests",
            dependencies: ["AniworldKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)

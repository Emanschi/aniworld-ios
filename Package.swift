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
        // Pure sync logic of the app (merge, conflict detection, backups). Not part of the app build
        // (XcodeGen compiles the files directly); exists only so `swift test` can cover it on Linux.
        .target(
            name: "AniworldSyncLogic",
            dependencies: ["AniworldKit"],
            path: "App/Sources/Persistence",
            sources: ["LibraryModels.swift", "SyncSnapshot.swift", "LibraryMerge.swift",
                      "SyncConflict.swift", "LibraryBackup.swift"]
        ),
        .executableTarget(
            name: "aniworld-smoke",
            dependencies: ["AniworldKit"]
        ),
        .testTarget(
            name: "AniworldKitTests",
            dependencies: ["AniworldKit"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "AniworldSyncLogicTests",
            dependencies: ["AniworldSyncLogic", "AniworldKit"]
        ),
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NoopCloudSync",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "NoopCloudSync", targets: ["NoopCloudSync"]),
        .executable(name: "noop-cloud-snapshot", targets: ["NoopCloudSnapshot"]),
        .executable(name: "noop-cloud-upload", targets: ["NoopCloudUpload"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "NoopCloudSync",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "NoopCloudSnapshot",
            dependencies: ["NoopCloudSync"]
        ),
        .executableTarget(
            name: "NoopCloudUpload",
            dependencies: ["NoopCloudSync"]
        ),
        .testTarget(name: "NoopCloudSyncTests", dependencies: ["NoopCloudSync"]),
    ]
)

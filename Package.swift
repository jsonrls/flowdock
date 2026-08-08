// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Flowdock",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Flowdock", targets: ["Flowdock"])
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite"
        ),
        .executableTarget(
            name: "Flowdock",
            dependencies: ["CSQLite"],
            path: "Sources/Flowdock",
            resources: [
                .process("Resources")
            ]
        ),
    ]
)

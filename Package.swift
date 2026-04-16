// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "JiraMenu",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "JiraBar", targets: ["JiraBar"]),
    ],
    targets: [
        .executableTarget(
            name: "JiraBar",
            path: "Sources",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "JiraBarTests",
            dependencies: ["JiraBar"]
        ),
    ],
    swiftLanguageModes: [.v6]
)

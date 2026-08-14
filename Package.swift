// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "thepfuck",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ThepfuckCore", targets: ["ThepfuckCore"]),
        .executable(name: "thepfuck", targets: ["thepfuck"]),
        .executable(name: "thepfuck-tests", targets: ["thepfuck-tests"]),
    ],
    targets: [
        .target(name: "ThepfuckCore"),
        .executableTarget(
            name: "thepfuck",
            dependencies: ["ThepfuckCore"],
            path: "Sources/thepfuck"
        ),
        .executableTarget(
            name: "thepfuck-tests",
            dependencies: ["ThepfuckCore"],
            path: "Tests/ThepfuckCoreTests"
        ),
    ]
)

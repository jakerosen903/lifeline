// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LifelineKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "LifelineKit", targets: ["LifelineKit"]),
        .executable(name: "lifeline", targets: ["lifeline"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.19"),
    ],
    targets: [
        .target(
            name: "LifelineKit",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift"), .product(name: "ZIPFoundation", package: "ZIPFoundation")],
            resources: [.copy("Extraction/Prompts"), .copy("Interviewer/Prompts/interviewer.v1.md"), .copy("Arc/FixedResponses")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "lifeline",
            dependencies: ["LifelineKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "LifelineKitTests",
            dependencies: ["LifelineKit"],
            resources: [.copy("../Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)

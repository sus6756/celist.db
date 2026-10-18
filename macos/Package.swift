// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CelistDB",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CelistDB", targets: ["CelistDB"]),
        .library(name: "CelistDBCore", targets: ["CelistDBCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "CelistDBCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/CelistDBCore"
        ),
        .executableTarget(
            name: "CelistDB",
            dependencies: [
                "CelistDBCore",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/CelistDB"
        ),
        .testTarget(
            name: "CelistDBCoreTests",
            dependencies: ["CelistDBCore"],
            path: "Tests/CelistDBCoreTests"
        ),
        .executableTarget(
            name: "CelistDBTests",
            dependencies: ["CelistDBCore"],
            path: "Sources/CelistDBTests"
        )
    ]
)

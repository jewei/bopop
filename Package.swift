// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Bopop",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "BopopKit", targets: ["BopopKit"]),
        .executable(name: "Bopop", targets: ["Bopop"])
    ],
    targets: [
        .target(
            name: "BopopKit",
            resources: [.copy("Resources/emoji.json")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .executableTarget(
            name: "Bopop",
            dependencies: ["BopopKit"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "BopopKitTests",
            dependencies: ["BopopKit"]
        )
    ],
    swiftLanguageModes: [.v6]
)

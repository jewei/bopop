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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.3")
    ],
    targets: [
        .target(
            name: "BopopKit",
            resources: [.copy("Resources/emoji.json")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .executableTarget(
            name: "Bopop",
            dependencies: [
                "BopopKit",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)],
            linkerSettings: [
                // The bundled app loads Sparkle from Contents/Frameworks.
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks"
                ])
            ]
        ),
        .testTarget(
            name: "BopopKitTests",
            dependencies: ["BopopKit"]
        )
    ],
    swiftLanguageModes: [.v6]
)

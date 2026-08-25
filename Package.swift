// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "screend",
    platforms: [.macOS("14.2")],
    targets: [
        .executableTarget(
            name: "screend",
            path: "Sources/screend",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/Info.plist",
                ])
            ]
        )
    ]
)

// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "screend",
    platforms: [.macOS("14.2")],
    targets: [
        // Pure logic, kept free of Core Audio so it can be unit tested without a device.
        .target(name: "ScreendCore", path: "Sources/ScreendCore"),
        .executableTarget(
            name: "screend",
            dependencies: ["ScreendCore"],
            path: "Sources/screend",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/Info.plist",
                ])
            ]
        ),
        .testTarget(name: "ScreendCoreTests", dependencies: ["ScreendCore"],
                    path: "Tests/ScreendCoreTests"),
    ]
)

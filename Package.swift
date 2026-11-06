// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WhereAmIP",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WhereAmIP", targets: ["WhereAmIP"])
    ],
    targets: [
        .executableTarget(
            name: "WhereAmIP",
            path: "Sources/WhereAmIP",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Network"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("IOKit"),
                .linkedFramework("UserNotifications")
            ]
        )
    ]
)

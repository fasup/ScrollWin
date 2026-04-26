// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScrollMouseWin",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "ScrollMouseWin",       targets: ["ScrollMouseWin"]),
        .executable(name: "ScrollMouseWinDaemon", targets: ["ScrollMouseWinDaemon"]),
    ],
    targets: [
        .executableTarget(name: "ScrollMouseWin"),
        .executableTarget(name: "ScrollMouseWinDaemon"),
    ]
)

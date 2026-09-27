// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "DambakMD",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "DambakMD", targets: ["DambakMD"])],
    dependencies: [.package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.7.0")],
    targets: [
        .target(name: "DambakCore", dependencies: [.product(name: "Markdown", package: "swift-markdown")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "DambakMD", dependencies: ["DambakCore"], resources: [.copy("Resources")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "DambakSelfTest", dependencies: ["DambakCore"], path: "Tests/DambakSelfTest", swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)

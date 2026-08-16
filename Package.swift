// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "md2png",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "md2png", targets: ["MD2PNG"])
    ],
    targets: [
        .executableTarget(
            name: "MD2PNG",
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("WebKit")
            ]
        ),
        .testTarget(
            name: "MD2PNGTests",
            dependencies: ["MD2PNG"]
        )
    ]
)

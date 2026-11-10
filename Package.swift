// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AirTranslate",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AirTranslate", targets: ["AirTranslate"])
    ],
    dependencies: [.package(path: "Vendor/argmax-oss-swift-main"), .package(path: "Vendor/silero-vad-swift-main")],
    targets: [
        .target(name: "AirTranslateCore"),
        .executableTarget(
            name: "AirTranslate",
            dependencies: ["AirTranslateCore", .product(name: "WhisperKit", package: "argmax-oss-swift-main"), .product(name: "SileroVAD", package: "silero-vad-swift-main")],
            linkerSettings: [
                .linkedFramework("AVFAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Security"),
                .linkedFramework("Speech"),
                .unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "Translation"])
            ]
        ),
        .testTarget(
            name: "AirTranslateCoreTests",
            dependencies: [
                "AirTranslateCore",
                "AirTranslate"
            ]
        )
    ]
)

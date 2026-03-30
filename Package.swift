// swift-tools-version: 5.9
// SkillsMaster — Native macOS Agent Skills Manager
// This is the Swift Package Manager project configuration file, similar to Go's go.mod or Python's pyproject.toml

import PackageDescription

let package = Package(
    name: "SkillsMaster",
    defaultLocalization: "en",

    // Specify minimum platform: macOS 14 (Sonoma), because we use the @Observable macro (new feature in macOS 14+)
    platforms: [.macOS(.v14)],

    // External dependencies, similar to Go modules or pip install
    dependencies: [
        // Yams: YAML parser library for Swift, used to parse SKILL.md frontmatter
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),

        // Apple's official Markdown parsing library, used to render the body of SKILL.md
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.7.3"),

    ],

    targets: [
        // Main application target (executable), similar to Go's main package
        .executableTarget(
            name: "SkillsMaster",
            dependencies: [
                "Yams",
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "Sources/SkillsMaster",
            // resources array tells SPM to bundle specified files into Bundle.module
            // .process optimizes based on file type (e.g., PNG compression), .copy copies as is
            // .icns files need to use .copy to preserve original format, as SPM doesn't recognize .icns type
            resources: [
                .process("Resources/Localization"),
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/AgentIcons")
            ]
        ),

        // Unit test target, similar to Go's _test.go files
        .testTarget(
            name: "SkillsMasterTests",
            dependencies: ["SkillsMaster"],
            path: "Tests/SkillsMasterTests"
        ),
    ]
)

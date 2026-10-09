// swift-tools-version:6.0
import PackageDescription

// A native (Swift) plugin only; there is no web build. `nucleus.plugin.json` is bundled as a resource.
let package = Package(
    name: "MarkdownPlugin",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "MarkdownPlugin", targets: ["MarkdownPlugin"]),
    ],
    dependencies: [
        .package(path: "../../nucleus-native-plugins"),
        .package(path: "../../apps/notes/plugin-kit"),
        .package(url: "https://github.com/NucleusHub/nucleus-native-ui", from: "0.3.0"),
    ],
    targets: [
        .target(
            name: "MarkdownPlugin",
            dependencies: [
                .product(name: "NucleusPlugins", package: "nucleus-native-plugins"),
                .product(name: "NotesPluginKit", package: "plugin-kit"),
                .product(name: "NucleusUI", package: "nucleus-native-ui"),
            ],
            path: ".",
            sources: ["native/Sources"],
            resources: [.copy("nucleus.plugin.json")]
        ),
        .testTarget(
            name: "MarkdownPluginTests",
            dependencies: [
                "MarkdownPlugin",
                .product(name: "NucleusPlugins", package: "nucleus-native-plugins"),
                .product(name: "NotesPluginKit", package: "plugin-kit"),
                .product(name: "NucleusUI", package: "nucleus-native-ui"),
            ],
            path: "native/Tests"
        ),
    ]
)

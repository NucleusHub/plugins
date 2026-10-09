// swift-tools-version:6.0
import PackageDescription

// A native (Swift) plugin only; there is no web build. `nucleus.plugin.json` is bundled as a resource.
let package = Package(
    name: "DailyNotePlugin",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "DailyNotePlugin", targets: ["DailyNotePlugin"]),
    ],
    dependencies: [
        .package(path: "../../nucleus-native-plugins"),
        .package(path: "../../apps/notes/plugin-kit"),
        .package(url: "https://github.com/NucleusHub/nucleus-native-ui", from: "0.3.0"),
    ],
    targets: [
        .target(
            name: "DailyNotePlugin",
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
            name: "DailyNotePluginTests",
            dependencies: [
                "DailyNotePlugin",
                .product(name: "NucleusPlugins", package: "nucleus-native-plugins"),
                .product(name: "NotesPluginKit", package: "plugin-kit"),
                .product(name: "NucleusUI", package: "nucleus-native-ui"),
            ],
            path: "native/Tests"
        ),
    ]
)

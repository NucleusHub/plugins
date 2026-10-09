// swift-tools-version:6.0
import PackageDescription

// A native (Swift) plugin only; there is no web build. `nucleus.plugin.json` is bundled as a resource.
let package = Package(
    name: "TodoCardPlugin",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "TodoCardPlugin", targets: ["TodoCardPlugin"]),
    ],
    dependencies: [
        .package(path: "../../nucleus-native-plugins"),
        .package(path: "../../apps/notes/plugin-kit"),
        .package(url: "https://github.com/NucleusHub/nucleus-native-ui", from: "0.3.0"),
    ],
    targets: [
        .target(
            name: "TodoCardPlugin",
            dependencies: [
                .product(name: "NucleusPlugins", package: "nucleus-native-plugins"),
                .product(name: "NotesPluginKit", package: "plugin-kit"),
                .product(name: "NucleusUI", package: "nucleus-native-ui"),
            ],
            path: ".",
            exclude: ["native/Tests"],
            sources: ["native/Sources"],
            resources: [.copy("nucleus.plugin.json")]
        ),
        .testTarget(
            name: "TodoCardPluginTests",
            dependencies: ["TodoCardPlugin"],
            path: "native/Tests"
        ),
    ]
)

// swift-tools-version:6.0
import PackageDescription

// The native (Swift) build of this plugin. `nucleus.plugin.json` is its manifest for every runtime,
// and is bundled as a resource so the Node and Swift sides read the same file.
let package = Package(
    name: "AnimeSourcePlugin",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AnimeSourcePlugin", targets: ["AnimeSourcePlugin"]),
    ],
    dependencies: [
        .package(path: "../../nucleus-native-plugins"),
        .package(path: "../../apps/watchlist/plugin-kit"),
    ],
    targets: [
        .target(
            name: "AnimeSourcePlugin",
            dependencies: [
                .product(name: "NucleusPlugins", package: "nucleus-native-plugins"),
                .product(name: "WatchlistPluginKit", package: "plugin-kit"),
            ],
            path: ".",
            exclude: ["client", "icon.svg", "native/Tests"],
            sources: ["native/Sources"],
            resources: [.copy("nucleus.plugin.json")]
        ),
        .testTarget(
            name: "AnimeSourcePluginTests",
            dependencies: ["AnimeSourcePlugin"],
            path: "native/Tests",
            resources: [.copy("kitsu-search.json")]
        ),
    ]
)

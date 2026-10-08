// swift-tools-version:6.0
import PackageDescription

// A native (Swift) plugin only; there is no web build. `nucleus.plugin.json` is bundled as a resource.
let package = Package(
    name: "AchievementsPlugin",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "AchievementsPlugin", targets: ["AchievementsPlugin"]),
    ],
    dependencies: [
        .package(path: "../../nucleus-native-plugins"),
        .package(path: "../../apps/todo/plugin-kit"),
        .package(url: "https://github.com/NucleusHub/nucleus-native-ui", from: "0.3.0"),
    ],
    targets: [
        .target(
            name: "AchievementsPlugin",
            dependencies: [
                .product(name: "NucleusPlugins", package: "nucleus-native-plugins"),
                .product(name: "TodoPluginKit", package: "plugin-kit"),
                .product(name: "NucleusUI", package: "nucleus-native-ui"),
            ],
            path: ".",
            sources: ["native/Sources"],
            resources: [.copy("nucleus.plugin.json")]
        ),
    ]
)

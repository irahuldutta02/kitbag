// swift-tools-version: 6.0
import PackageDescription

// Layout: Core (shared protocol/registry) <- Tools/* (independent, never import each other) <- App.
let package = Package(
  name: "Kitbag",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "Kitbag", targets: ["Kitbag"])],
  targets: [
    .target(name: "KitbagCore", path: "Core/Sources"),
    .testTarget(name: "KitbagCoreTests", dependencies: ["KitbagCore"], path: "Core/Tests"),

    .target(name: "FileShelf", dependencies: ["KitbagCore"], path: "Tools/FileShelf/Sources"),
    .testTarget(name: "FileShelfTests", dependencies: ["FileShelf"], path: "Tools/FileShelf/Tests"),

    .target(
      name: "SystemMonitor", dependencies: ["KitbagCore"], path: "Tools/SystemMonitor/Sources"),
    .testTarget(
      name: "SystemMonitorTests", dependencies: ["SystemMonitor"], path: "Tools/SystemMonitor/Tests"
    ),

    .target(name: "SpeedTest", dependencies: ["KitbagCore"], path: "Tools/SpeedTest/Sources"),
    .testTarget(name: "SpeedTestTests", dependencies: ["SpeedTest"], path: "Tools/SpeedTest/Tests"),

    .target(name: "DevTools", dependencies: ["KitbagCore"], path: "Tools/DevTools/Sources"),
    .testTarget(name: "DevToolsTests", dependencies: ["DevTools"], path: "Tools/DevTools/Tests"),

    .target(
      name: "Audio", dependencies: ["KitbagCore"], path: "Tools/Audio/Sources"),
    .testTarget(
      name: "AudioTests", dependencies: ["Audio"], path: "Tools/Audio/Tests"),

    .target(name: "Blip", dependencies: ["KitbagCore"], path: "Tools/Blip/Sources"),
    .testTarget(name: "BlipTests", dependencies: ["Blip"], path: "Tools/Blip/Tests"),

    .target(name: "Apps", dependencies: ["KitbagCore"], path: "Tools/Apps/Sources"),
    .testTarget(name: "AppsTests", dependencies: ["Apps"], path: "Tools/Apps/Tests"),

    .target(name: "Dictation", dependencies: ["KitbagCore"], path: "Tools/Dictation/Sources"),
    .testTarget(name: "DictationTests", dependencies: ["Dictation"], path: "Tools/Dictation/Tests"),

    .executableTarget(
      name: "Kitbag",
      dependencies: [
        "KitbagCore", "FileShelf", "SystemMonitor", "SpeedTest", "DevTools",
        "Audio",
        "Blip", "Apps", "Dictation",
      ],
      path: "App/Sources"),
  ],
  swiftLanguageModes: [.v5]
)

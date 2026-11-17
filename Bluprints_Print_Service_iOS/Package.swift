// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "BluprintsProtocol",
    products: [.library(name: "BluprintsProtocol", targets: ["BluprintsProtocol"])],
    targets: [
        .target(name: "BluprintsProtocol", path: "BluprintsPrintService", exclude: ["BLEPrinter.swift", "JobInbox.swift", "ContentView.swift", "BluprintsPrintServiceApp.swift", "Info.plist"], sources: ["PrintJob.swift"]),
        .testTarget(name: "BluprintsProtocolTests", dependencies: ["BluprintsProtocol"], path: "Tests")
    ]
)

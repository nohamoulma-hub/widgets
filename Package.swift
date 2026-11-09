// swift-tools-version: 5.9
import PackageDescription

// Trois blocs: DeskKit (le socle commun), ProjectsWidget (le widget Projets)
// et DeskWidgets (l'app qui les affiche sur le bureau).
let package = Package(
    name: "DeskWidgets",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "DeskWidgets", targets: ["DeskWidgets"])
    ],
    targets: [
        .target(name: "DeskKit"),
        .target(name: "ProjectsWidget", dependencies: ["DeskKit"]),
        .executableTarget(name: "DeskWidgets", dependencies: ["DeskKit", "ProjectsWidget"])
    ]
)

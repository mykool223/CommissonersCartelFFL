// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CartelKit",
    platforms: [
        .iOS(.v18),
        // macOS is listed so the package can be built and tested from the command
        // line without Xcode. The app target itself is iOS-only.
        .macOS(.v14),
    ],
    products: [
        .library(name: "CartelCore", targets: ["CartelCore"]),
        .library(name: "CartelESPN", targets: ["CartelESPN"]),
        .library(name: "CartelSupabase", targets: ["CartelSupabase"]),
    ],
    targets: [
        // Models, protocols, mock data and the HTTP transport seam. No external deps.
        .target(name: "CartelCore"),

        // Read-only client for ESPN's undocumented fantasy endpoints.
        .target(name: "CartelESPN", dependencies: ["CartelCore"]),

        // PostgREST/GoTrue client for league-authored content.
        .target(name: "CartelSupabase", dependencies: ["CartelCore"]),

        .testTarget(name: "CartelCoreTests", dependencies: ["CartelCore"]),
        .testTarget(
            name: "CartelESPNTests",
            dependencies: ["CartelESPN"],
            resources: [.process("Fixtures")]
        ),
        .testTarget(name: "CartelSupabaseTests", dependencies: ["CartelSupabase"]),
    ]
)

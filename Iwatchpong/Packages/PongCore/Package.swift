// swift-tools-version:5.9
import PackageDescription

// PongCore is the platform-independent heart of WristPong:
//   Motion  -> filtering, calibration, world-frame mapping
//   Swing   -> swing detection + stroke classification (forehand/backhand, topspin, backspin, smash, lob ...)
//   Physics -> ball flight with spin (Magnus), table bounce friction, net, shot solver
//   Game    -> ITTF-style rules, match engine, rally referee, drills, shot model
//   AI      -> opponents with different playing styles
//   Wire    -> messages exchanged between Watch and iPhone
//
// Foundation only: it builds and tests on macOS, Linux and Windows toolchains
// as well as iOS/watchOS. No CoreMotion, no SwiftUI here.
let package = Package(
    name: "PongCore",
    platforms: [.iOS(.v16), .watchOS(.v9), .macOS(.v13)],
    products: [
        .library(name: "PongCore", targets: ["PongCore"])
    ],
    targets: [
        .target(name: "PongCore"),
        .testTarget(name: "PongCoreTests", dependencies: ["PongCore"])
    ]
)

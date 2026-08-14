// swift-tools-version: 5.9
import PackageDescription

// 責務分離はモジュール境界で「コンパイル時に」保証する。
//
//   Presentation ──▶ Domain
//   Data         ──▶ Domain
//   Infrastructure ▶ Domain, Data
//   App(composition root) ──▶ すべて
//
// 逆方向・横断の import はモジュールが依存関係に無いためビルドが通らない。
// 追加で ArchitectureTests が import 文を静的に検査し、意図せぬ依存追加を検出する。
let package = Package(
    name: "UsefulMapKit",
    defaultLocalization: "ja",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Data", targets: ["Data"]),
        .library(name: "Infrastructure", targets: ["Infrastructure"]),
        .library(name: "Presentation", targets: ["Presentation"])
    ],
    targets: [
        // 純粋なモデルとポリシー。Foundation 以外に依存しない。
        .target(name: "Domain", resources: [.process("Resources")]),

        // 永続化と外部 URL 契約のアダプタ。UI にも MapKit にも依存しない。
        .target(name: "Data", dependencies: ["Domain"]),

        // MapKit / CoreLocation / UIKit などプラットフォーム SDK との境界。
        .target(name: "Infrastructure", dependencies: ["Domain", "Data"]),

        // SwiftUI 画面と ViewModel。Domain のプロトコルにのみ依存する。
        .target(name: "Presentation", dependencies: ["Domain"], resources: [.process("Resources")]),

        .testTarget(name: "DomainTests", dependencies: ["Domain"]),
        .testTarget(name: "DataTests", dependencies: ["Data", "Domain"]),
        .testTarget(name: "InfrastructureTests", dependencies: ["Infrastructure", "Domain"]),
        .testTarget(name: "PresentationTests", dependencies: ["Presentation", "Domain"]),
        .testTarget(name: "ArchitectureTests")
    ]
)

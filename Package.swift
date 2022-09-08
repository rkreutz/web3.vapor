// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "web3.vapor",
    platforms: [.macOS(.v11)],
    products: [
        .library(
            name: "web3.vapor",
            targets: ["Web3Vapor"]),
    ],
    dependencies: [
//        .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
        .package(url: "https://github.com/rkreutz/vapor.git", from: "4.65.2"), // Reduces availability of Concurrency code so it can be run on macOS 10.15 and above
//        .package(url: "https://github.com/vapor/fluent.git", from: "4.0.0"),
        .package(url: "https://github.com/rkreutz/fluent.git", from: "4.5.1"), // Reduces availability of Concurrency code so it can be run on macOS 10.15 and above
        .package(url: "https://github.com/argentlabs/web3.swift", branch: "develop"),
    ],
    targets: [
        .target(
            name: "Web3Vapor",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "web3.swift", package: "web3.swift"),
            ]),
    ]
)

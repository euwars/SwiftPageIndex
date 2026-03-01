// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "SwiftPageIndex",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
  ],
  products: [
    .library(name: "SwiftPageIndex", targets: ["SwiftPageIndex"]),
  ],
  dependencies: [
    .package(url: "https://github.com/mattt/AnyLanguageModel", branch: "main"),
    .package(url: "https://github.com/euwars/SwiftPDF", from: "1.0.0"),
    .package(url: "https://github.com/scinfu/SwiftSoup", from: "2.7.0"),
    .package(url: "https://github.com/swiftlang/swift-testing", from: "0.12.0"),
  ],
  targets: [
    .target(
      name: "SwiftPageIndex",
      dependencies: [
        .product(name: "AnyLanguageModel", package: "AnyLanguageModel"),
        .product(name: "SwiftPDF", package: "SwiftPDF"),
        .product(name: "SwiftSoup", package: "SwiftSoup"),
      ],
    ),
    .testTarget(
      name: "SwiftPageIndexTests",
      dependencies: [
        "SwiftPageIndex",
        .product(name: "Testing", package: "swift-testing"),
      ],
      resources: [
        .copy("Fixtures"),
      ],
    ),
  ],
)

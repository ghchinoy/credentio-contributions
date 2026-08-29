// swift-tools-version: 6.0
// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import PackageDescription

var credentioKitDeps: [Target.Dependency] = []
var credentioKitLinkerSettings: [LinkerSetting] = []
var extraTargets: [Target] = []

// Dynamically link native CredentioC.xcframework:
// 1. Local xcframework if built on host or specified via CREDENTIO_C_XCFRAMEWORK_PATH
// 2. Remote GitHub Release binaryTarget for standalone SwiftPM consumers
let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let customXCFPath = ProcessInfo.processInfo.environment["CREDENTIO_C_XCFRAMEWORK_PATH"]
let nativeXcframeworkURL = customXCFPath.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    ?? packageDir.appendingPathComponent("CredentioC.xcframework")

// Prebuilt binary distribution release metadata
let releaseVersion = "0.1.5"
let remoteChecksum = "b0a67d82a3c5465ac328bbed9cf2234814ae0c07f0deccd76a5be5a6b303e621"
let remoteURL = "https://github.com/ghchinoy/credentio-contributions/releases/download/v\(releaseVersion)/CredentioC.xcframework.zip"

if FileManager.default.fileExists(atPath: nativeXcframeworkURL.path) {
    credentioKitDeps.append("CredentioC")
    credentioKitLinkerSettings.append(.linkedLibrary("c++"))
    // SwiftPM requires package-relative path for downstream consumers; custom absolute paths only apply in root-package dev mode
    let binaryPath = customXCFPath != nil ? nativeXcframeworkURL.path : "CredentioC.xcframework"
    extraTargets.append(
        .binaryTarget(
            name: "CredentioC",
            path: binaryPath
        )
    )
} else if ProcessInfo.processInfo.environment["CREDENTIO_SOURCE_ONLY"] == nil && remoteChecksum != "PLACEHOLDER_CHECKSUM" {
    credentioKitDeps.append("CredentioC")
    credentioKitLinkerSettings.append(.linkedLibrary("c++"))
    extraTargets.append(
        .binaryTarget(
            name: "CredentioC",
            url: remoteURL,
            checksum: remoteChecksum
        )
    )
}

let package = Package(
    name: "CredentioKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "CredentioKit",
            targets: ["CredentioKit"]
        ),
        .executable(
            name: "credentio-cli",
            targets: ["credentio-cli"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "CredentioKit",
            dependencies: credentioKitDeps,
            path: "Sources/CredentioKit",
            linkerSettings: credentioKitLinkerSettings
        ),
        .executableTarget(
            name: "credentio-cli",
            dependencies: [
                "CredentioKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/credentio-cli",
            linkerSettings: credentioKitLinkerSettings
        ),
        .testTarget(
            name: "CredentioKitTests",
            dependencies: [
                "CredentioKit"
            ],
            path: "Tests/CredentioKitTests",
            linkerSettings: credentioKitLinkerSettings
        ),
    ] + extraTargets
)

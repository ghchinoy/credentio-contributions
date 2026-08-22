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

// Dynamically link native CredentioC.xcframework if built on host
let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let nativeXcframeworkURL = packageDir.appendingPathComponent("CredentioC.xcframework")

if FileManager.default.fileExists(atPath: nativeXcframeworkURL.path) {
    credentioKitDeps.append("CredentioC")
    credentioKitLinkerSettings.append(.linkedLibrary("c++"))
    extraTargets.append(
        .binaryTarget(
            name: "CredentioC",
            path: "CredentioC.xcframework"
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
    ],
    targets: [
        .target(
            name: "CredentioKit",
            dependencies: credentioKitDeps,
            path: "Sources/CredentioKit",
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

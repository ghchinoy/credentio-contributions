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

/// `ProvenanceEngine` backed by the Google Credentio `c2pa_validate` or `c2patool` CLI tool.
///
/// Executes the CLI binary as an asynchronous subprocess, captures the `crjson`
/// output, measures execution time, and maps the result into `ProvenanceReport`.
public struct CredentioCLIEngine: ProvenanceEngine {
    public let id = "credentio"
    public let displayName = "Credentio CLI / c2patool"

    /// Explicit path to the CLI binary, or `nil` to look in standard paths.
    public var executablePath: String?
    /// Optional path to claim signer trust anchors PEM.
    public var claimSignerTrustPath: String?
    /// Optional path to TSA trust anchors PEM.
    public var tsaTrustPath: String?

    public init(
        executablePath: String? = nil,
        claimSignerTrustPath: String? = nil,
        tsaTrustPath: String? = nil
    ) {
        self.executablePath = executablePath
        self.claimSignerTrustPath = claimSignerTrustPath
        self.tsaTrustPath = tsaTrustPath
    }

    /// Locates the `c2pa_validate`, `c2patool`, or `credentio` executable.
    public static func resolveExecutableURL(customPath: String? = nil) -> URL? {
        if let customPath, !customPath.isEmpty {
            let url = URL(fileURLWithPath: (customPath as NSString).expandingTildeInPath)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        let binaryNames = ["c2pa_validate", "c2patool", "credentio"]
        let candidateDirs = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            (NSHomeDirectory() as NSString).appendingPathComponent(".cargo/bin"),
            (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin"),
            (NSHomeDirectory() as NSString).appendingPathComponent("bin"),
            (NSHomeDirectory() as NSString).appendingPathComponent("projects/credentio/bazel-bin/tools"),
            "/workspace/credentio/bazel-bin/tools"
        ]

        // Check system $PATH environment variable
        var envDirs: [String] = []
        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            envDirs = envPath.split(separator: ":").map(String.init)
        }

        let allDirs = envDirs + candidateDirs

        for binary in binaryNames {
            // Check inside application bundle Resources or MacOS
            if let bundleURL = Bundle.main.url(forResource: binary, withExtension: nil) {
                return bundleURL
            }
            if let auxURL = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(binary),
               FileManager.default.isExecutableFile(atPath: auxURL.path) {
                return auxURL
            }

            for dir in allDirs {
                let fullPath = (dir as NSString).appendingPathComponent(binary)
                if FileManager.default.isExecutableFile(atPath: fullPath) {
                    return URL(fileURLWithPath: fullPath)
                }
            }
        }

        return nil
    }

    public func read(url: URL) async throws -> ProvenanceReport {
        let mediaType = SupportedFormats.mediaType(for: url)
        guard let format = mediaType else {
            throw ProvenanceError.unsupportedFormat(url.pathExtension)
        }

        guard let executableURL = Self.resolveExecutableURL(customPath: executablePath) else {
            throw ProvenanceError.engineFailure(
                "No C2PA CLI tool found (checked c2pa_validate, c2patool, credentio). Please ensure c2patool or c2pa_validate is in PATH."
            )
        }

        let isC2PATool = executableURL.lastPathComponent == "c2patool"
        let isCredentio = executableURL.lastPathComponent == "credentio"
        var arguments: [String] = []

        if isC2PATool {
            arguments = [url.path]
        } else if isCredentio {
            arguments = ["validate", url.path, "-json", "-skip-trust-checks"]
        } else {
            arguments = [
                "--asset=\(url.path)",
                "--output_format=crjson"
            ]
            if let claimSignerTrustPath, !claimSignerTrustPath.isEmpty {
                arguments.append("--claim_signer_trust=\(claimSignerTrustPath)")
            }
            if let tsaTrustPath, !tsaTrustPath.isEmpty {
                arguments.append("--tsa_trust=\(tsaTrustPath)")
            }
        }

        let clock = ContinuousClock()
        let start = clock.now

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw ProvenanceError.engineFailure("Failed to spawn \(executableURL.lastPathComponent): \(error.localizedDescription)")
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let elapsed = start.duration(to: clock.now)
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        if stdout.contains("{") {
            let jsonPayload = Self.extractJSON(from: stdout)
            return CredentioCrjsonMapper.mapReport(
                json: jsonPayload,
                mediaType: format,
                elapsed: elapsed,
                engineInternalElapsed: nil,
                engineID: id,
                engineName: isC2PATool ? "c2patool (CLI)" : displayName
            )
        }

        if process.terminationStatus != 0 || stdout.isEmpty {
            if stderr.contains("No C2PA") || stderr.contains("not found") || stderr.contains("No claim found")
                || stdout.contains("No C2PA") || stdout.contains("No claim found") {
                return .empty(
                    engineID: id,
                    engineName: displayName,
                    elapsed: elapsed,
                    mediaType: format
                )
            }
            return .empty(
                engineID: id,
                engineName: displayName,
                elapsed: elapsed,
                mediaType: format
            )
        }

        let jsonPayload = Self.extractJSON(from: stdout)
        return CredentioCrjsonMapper.mapReport(
            json: jsonPayload,
            mediaType: format,
            elapsed: elapsed,
            engineInternalElapsed: nil,
            engineID: id,
            engineName: isC2PATool ? "c2patool (CLI)" : displayName
        )
    }

    /// Strips CLI decorative prefixes to isolate the raw JSON.
    static func extractJSON(from output: String) -> String {
        if let range = output.range(of: "Validation Result (crjson):\n") {
            return String(output[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let firstBrace = output.firstIndex(of: "{"),
           let lastBrace = output.lastIndex(of: "}") {
            return String(output[firstBrace...lastBrace])
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

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

import ArgumentParser
import CredentioKit
import Foundation

@main
struct CredentioCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "credentio-cli",
        abstract: "Google Credentio C2PA Content Credentials Command-Line Validator",
        version: "0.1.0",
        subcommands: [Validate.self],
        defaultSubcommand: Validate.self
    )
}

struct Validate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Validate C2PA content credentials in a media asset"
    )

    @Argument(help: "Path to media asset (image, video, audio, document)")
    var path: String

    @Option(name: [.short, .customLong("media-type")], help: "Optional IANA MIME type")
    var mediaType: String?

    @Flag(name: .customLong("json"), help: "Output structured JSON")
    var jsonOutput: Bool = false

    @Option(name: .customLong("claim-signer-trust"), help: "Path to claim signer trust anchors PEM")
    var claimSignerTrust: String?

    @Option(name: .customLong("tsa-trust"), help: "Path to TSA trust anchors PEM")
    var tsaTrust: String?

    @Flag(name: .customLong("skip-trust-checks"), inversion: .prefixedNo, help: "Skip certificate trust checks")
    var skipTrustChecks: Bool = true

    func run() async throws {
        let fileURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            FileHandle.standardError.write(Data("Error: file not found at \(fileURL.path)\n".utf8))
            throw ExitCode(3)
        }

        let skipTrust = (claimSignerTrust != nil || tsaTrust != nil) ? false : skipTrustChecks

        let engine = CredentioNativeEngine(
            claimSignerTrustPath: claimSignerTrust,
            tsaTrustPath: tsaTrust,
            skipTrustChecks: skipTrust
        )

        do {
            let report = try await engine.read(url: fileURL)

            if jsonOutput {
                print(formatJSONOutput(report: report, fileURL: fileURL))
            } else {
                print(formatHumanOutput(report: report, fileURL: fileURL))
            }

            switch report.badge {
            case .signed:
                throw ExitCode(0)
            case .unsigned:
                throw ExitCode(1)
            case .invalid:
                throw ExitCode(2)
            }
        } catch let exitCode as ExitCode {
            throw exitCode
        } catch {
            FileHandle.standardError.write(Data("Validation error: \(error.localizedDescription)\n".utf8))
            throw ExitCode(3)
        }
    }

    private func formatHumanOutput(report: ProvenanceReport, fileURL: URL) -> String {
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        let sizeMB = Double(fileSize) / (1024.0 * 1024.0)

        var lines: [String] = [
            String(repeating: "=", count: 64),
            "  Google Credentio C2PA Validation Report",
            String(repeating: "=", count: 64),
            "Asset:       \(fileURL.lastPathComponent) (\(String(format: "%.2f MB", sizeMB)), \(report.mediaType ?? "unknown"))",
            "Path:        \(fileURL.path)",
            "Status:      \(report.badge.rawValue.uppercased())"
        ]

        if report.hasCredentials, let m = report.activeManifest {
            lines.append("Generator:   \(m.claimGenerator ?? "—")")
            lines.append("Signer:      \(m.signature?.issuer ?? "—")")
            lines.append("Format/Spec: \(m.format ?? "—") (C2PA \(report.specVersion ?? "—"))")
            lines.append("Assertions:  \(m.assertions.count) attached")
            lines.append("Statuses:    \(m.validationStatuses.count) reported")
        }

        if let core = report.engineInternalElapsed {
            let coreMs = Double(core.components.seconds) * 1000.0 + Double(core.components.attoseconds) / 1e15
            lines.append(String(format: "Core Time:   %.2f ms", coreMs))
        }
        let wallMs = Double(report.elapsed.components.seconds) * 1000.0 + Double(report.elapsed.components.attoseconds) / 1e15
        lines.append(String(format: "Wall Time:   %.2f ms", wallMs))
        lines.append(String(repeating: "=", count: 64))

        return lines.joined(separator: "\n")
    }

    private func formatJSONOutput(report: ProvenanceReport, fileURL: URL) -> String {
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        let coreMs: Double? = report.engineInternalElapsed.map {
            Double($0.components.seconds) * 1000.0 + Double($0.components.attoseconds) / 1e15
        }
        let wallMs = Double(report.elapsed.components.seconds) * 1000.0 + Double(report.elapsed.components.attoseconds) / 1e15

        var dict: [String: Any] = [
            "asset_path": fileURL.path,
            "byte_size": fileSize,
            "media_type": report.mediaType as Any,
            "engine_id": report.engineID,
            "has_credentials": report.hasCredentials,
            "badge": report.badge.rawValue,
            "spec_version": report.specVersion as Any,
            "elapsed_ms": wallMs,
            "core_ms": coreMs as Any
        ]

        if let m = report.activeManifest {
            dict["active_manifest"] = [
                "label": m.label,
                "title": m.title as Any,
                "claim_generator": m.claimGenerator as Any,
                "format": m.format as Any,
                "is_update_manifest": m.isUpdateManifest,
                "signature": [
                    "issuer": m.signature?.issuer as Any,
                    "algorithm": m.signature?.algorithm as Any,
                    "cert_serial_number": m.signature?.certChainSummary as Any
                ],
                "assertions_count": m.assertions.count,
                "validation_statuses_count": m.validationStatuses.count
            ]
        }

        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }
}

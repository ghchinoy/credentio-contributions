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

/// Maps Credentio's "crjson" and c2patool manifest store format into an engine-agnostic `ProvenanceReport`.
///
/// Supports both:
/// - Credentio format: Array of manifest dictionaries with nested validation statuses
/// - c2patool format: Dictionary of manifests with `active_manifest` key and root-level validation statuses
public enum CredentioCrjsonMapper {

    /// Maps raw crjson string into a `ProvenanceReport`.
    public static func mapReport(
        json: String,
        mediaType: String,
        elapsed: Duration,
        engineInternalElapsed: Duration? = nil,
        engineID: String = "credentio",
        engineName: String = "Credentio (Google)"
    ) -> ProvenanceReport {
        guard
            let root = (try? JSONSerialization.jsonObject(
                with: Data(json.utf8)
            )) as? [String: Any]
        else {
            return ProvenanceReport(
                engineID: engineID,
                engineName: engineName,
                hasCredentials: false,
                elapsed: elapsed,
                engineInternalElapsed: engineInternalElapsed,
                mediaType: mediaType,
                rawJSON: json
            )
        }

        var manifests: [Manifest] = []

        if let manifestsArray = root["manifests"] as? [[String: Any]] {
            for (index, dict) in manifestsArray.enumerated() {
                manifests.append(mapManifest(dict: dict, defaultLabel: "manifest_\(index)"))
            }
        } else if let manifestsDict = root["manifests"] as? [String: Any] {
            // c2patool / manifest-store structure: object keyed by label
            for (label, value) in manifestsDict {
                if let dict = value as? [String: Any] {
                    manifests.append(mapManifest(dict: dict, defaultLabel: label))
                }
            }
        }

        // Support active_manifest key pointing to specific manifest label (c2patool format)
        let activeLabel = root["active_manifest"] as? String
        var active: Manifest?
        var ingredients: [Manifest] = []

        if let activeLabel, let matched = manifests.first(where: { $0.label == activeLabel }) {
            active = matched
            ingredients = manifests.filter { $0.label != activeLabel }
        } else {
            active = manifests.first
            ingredients = manifests.count > 1 ? Array(manifests.dropFirst()) : []
        }

        // Fall back to root-level validation_status if active manifest has none nested
        if var activeManifest = active {
            if activeManifest.validationStatuses.isEmpty {
                let rootStatuses = (root["validation_status"] as? [[String: Any]])
                    ?? ((root["validation_results"] as? [String: Any])?["validation_status"] as? [[String: Any]])
                if let rootStatuses {
                    activeManifest.validationStatuses = mapValidationStatuses(rootStatuses)
                    active = activeManifest
                }
            }
        }

        if !mediaType.isEmpty {
            if active?.format == nil || active?.format?.isEmpty == true {
                active?.format = mediaType
            }
            for i in ingredients.indices {
                if ingredients[i].format == nil || ingredients[i].format?.isEmpty == true {
                    ingredients[i].format = mediaType
                }
            }
        }

        let validationResults = root["validation_results"] as? [String: Any]
        let specVersion = root["spec_version"] as? String
            ?? validationResults?["spec_version"] as? String
            ?? validationResults?["version"] as? String

        return ProvenanceReport(
            engineID: engineID,
            engineName: engineName,
            hasCredentials: active != nil,
            elapsed: elapsed,
            engineInternalElapsed: engineInternalElapsed,
            mediaType: mediaType,
            specVersion: specVersion,
            activeManifest: active,
            ingredientManifests: ingredients,
            rawJSON: json
        )
    }

    private static func mapManifest(dict: [String: Any], defaultLabel: String) -> Manifest {
        let label = dict["label"] as? String ?? defaultLabel
        let title = dict["title"] as? String
        let format = dict["format"] as? String
        let isUpdateManifest = dict["is_update_manifest"] as? Bool ?? false

        let claimDict = (dict["claim"] as? [String: Any])
            ?? (dict["claim.v2"] as? [String: Any])

        // Claim generator extraction
        var claimGenerator: String?
        if let genDict = (claimDict?["claim_generator_info"] as? [String: Any])
            ?? (dict["claim_generator_info"] as? [String: Any]) {
            let name = genDict["name"] as? String
            let version = cleanGeneratorVersion(genDict["version"] as? String)
            claimGenerator = [name, version].compactMap { $0 }.joined(separator: " ")
        } else {
            let genInfoList = (claimDict?["claim_generator_info"] as? [[String: Any]])
                ?? (dict["claim_generator_info"] as? [[String: Any]])
            if let first = genInfoList?.first {
                let name = first["name"] as? String
                let version = cleanGeneratorVersion(first["version"] as? String)
                claimGenerator = [name, version].compactMap { $0 }.joined(separator: " ")
            }
        }
        if claimGenerator == nil {
            claimGenerator = (claimDict?["claim_generator"] as? String) ?? (dict["claim_generator"] as? String)
        }

        // Signature extraction
        let sigDict = (claimDict?["signature_info"] as? [String: Any])
            ?? (dict["signature_info"] as? [String: Any])
            ?? (claimDict?["signature"] as? [String: Any])
            ?? (dict["signature"] as? [String: Any])
        let signature = mapSignature(sigDict)

        // Assertions extraction
        var assertions: [Assertion] = []
        if let assertionsDict = dict["assertions"] as? [String: Any] {
            for (assertionLabel, assertionValue) in assertionsDict {
                let kind = Assertion.Kind.classify(label: assertionLabel)
                let summary = summarizeAssertion(label: assertionLabel, value: assertionValue)
                assertions.append(Assertion(label: assertionLabel, kind: kind, summary: summary))
            }
        } else if let assertionsArray = dict["assertions"] as? [[String: Any]] {
            for entry in assertionsArray {
                guard let assertionLabel = entry["label"] as? String else { continue }
                let kind = Assertion.Kind.classify(label: assertionLabel)
                let summary = summarizeAssertion(label: assertionLabel, value: entry["data"] ?? entry)
                assertions.append(Assertion(label: assertionLabel, kind: kind, summary: summary))
            }
        }
        assertions.sort { $0.label < $1.label }

        // Validation status extraction
        var statuses: [ValidationStatus] = []
        if let validationObj = dict["validation"] as? [String: Any],
           let statusList = validationObj["status"] as? [[String: Any]] {
            statuses = mapValidationStatuses(statusList)
        } else if let statusList = dict["validation_status"] as? [[String: Any]] {
            statuses = mapValidationStatuses(statusList)
        } else if let valResults = dict["validationResults"] as? [String: Any] {
            for cat in ["failure", "informational", "success"] {
                if let catList = valResults[cat] as? [[String: Any]] {
                    statuses.append(contentsOf: mapValidationStatuses(catList, category: cat))
                }
            }
        }

        return Manifest(
            label: label,
            title: title,
            format: format,
            claimGenerator: claimGenerator,
            isUpdateManifest: isUpdateManifest,
            signature: signature,
            assertions: assertions,
            validationStatuses: statuses
        )
    }

    private static func mapSignature(_ dict: [String: Any]?) -> SignatureInfo? {
        guard let dict else { return nil }
        var issuer = dict["issuer"] as? String ?? dict["common_name"] as? String
        let certInfo = dict["certificateInfo"] as? [String: Any]
        if issuer == nil, let issObj = certInfo?["issuer"] as? [String: Any] {
            issuer = issObj["CN"] as? String
        }
        var certSummary = dict["cert_serial_number"] as? String
        if certSummary == nil {
            certSummary = certInfo?["serialNumber"] as? String
        }
        var time: Date?
        let timeString = dict["time"] as? String
            ?? dict["date_time"] as? String
            ?? (dict["timeStampInfo"] as? [String: Any])?["timestamp"] as? String
        if let timeString {
            time = ISO8601DateFormatter().date(from: timeString)
        }
        return SignatureInfo(
            issuer: issuer,
            algorithm: dict["alg"] as? String ?? dict["algorithm"] as? String,
            time: time,
            certChainSummary: certSummary
        )
    }

    private static func summarizeAssertion(label: String, value: Any) -> String? {
        guard let dict = value as? [String: Any] else { return nil }

        // 1. Actions assertion
        if let actions = dict["actions"] as? [[String: Any]] {
            let names = actions.compactMap { actionDict -> String? in
                guard let action = actionDict["action"] as? String else { return nil }
                if let dst = (actionDict["digitalSourceType"] as? String) ?? (actionDict["digital_source_type"] as? String),
                   !dst.isEmpty {
                    let cleanType = dst.split(separator: "/").last.map(String.init) ?? dst
                    return "\(action) (\(cleanType))"
                }
                return action
            }
            if !names.isEmpty { return names.joined(separator: ", ") }
        }

        // 2. Data hash assertion
        if let hashValue = dict["hash_value"] as? String {
            return "hash: \(hashValue.prefix(16))…"
        }

        // 3. AI Training and Mining assertion
        if label.contains("training-mining") || label.contains("data-mining") {
            if let entries = dict["entries"] as? [String: Any] {
                let formatted = entries.sorted(by: { $0.key < $1.key }).compactMap { key, val -> String? in
                    let shortKey = key.replacingOccurrences(of: "c2pa.", with: "").replacingOccurrences(of: "cawg.", with: "")
                    if let valDict = val as? [String: Any], let use = valDict["use"] as? String {
                        return "\(shortKey)=\(use)"
                    } else if let useStr = val as? String {
                        return "\(shortKey)=\(useStr)"
                    }
                    return nil
                }
                if !formatted.isEmpty {
                    return "AI Training: \(formatted.joined(separator: ", "))"
                }
            } else if let use = dict["use"] as? String {
                return "AI Training: \(use)"
            }
        }

        // 4. Digital Source Type assertion
        if label.contains("digital_source_type") || label.contains("digitalSourceType") {
            let typeVal = dict["digital_source_type"] as? String
                ?? dict["digitalSourceType"] as? String
                ?? dict["type"] as? String
            if let typeVal {
                let cleanType = typeVal.split(separator: "/").last.map(String.init) ?? typeVal
                return cleanType
            }
        }

        // 5. AI Generative Info assertion
        if label.contains("generative") || label.contains("inference") {
            if let modelDict = dict["model"] as? [String: Any] {
                let name = modelDict["name"] as? String
                let version = modelDict["version"] as? String
                let modelStr = [name, version].compactMap { $0 }.joined(separator: " ")
                if !modelStr.isEmpty {
                    return "model: \(modelStr)"
                }
            }
            if let modelName = dict["model_name"] as? String {
                return "model: \(modelName)"
            }
            if let prompt = dict["prompt"] as? String {
                return "prompt: \(prompt)"
            }
        }

        return nil
    }

    private static func mapValidationStatuses(_ array: [[String: Any]], category: String? = nil) -> [ValidationStatus] {
        array.compactMap { entry in
            guard let code = entry["code"] as? String else { return nil }
            var sev = severity(forCode: code)
            if category == "failure" {
                sev = .error
            } else if category == "informational" || category == "success" {
                sev = .info
            }
            return ValidationStatus(
                code: code,
                explanation: entry["explanation"] as? String,
                url: entry["url"] as? String,
                severity: sev
            )
        }
    }

    private static func severity(forCode code: String) -> ValidationStatus.Severity {
        let lowered = code.lowercased()
        // Note: 'untrusted' is currently classified as .error.
        // Reclassifying 'signingCredential.untrusted' to .warning is tracked as a policy decision in issue #6.
        if lowered.contains("not")
            || lowered.contains("invalid")
            || lowered.contains("mismatch")
            || lowered.contains("missing")
            || lowered.contains("untrusted")
            || lowered.contains("fail")
            || lowered.contains("error") {
            return .error
        }
        if lowered.contains("validated") || lowered.contains("trusted") || lowered.contains("success") || lowered.contains("ok") {
            return .info
        }
        return .warning
    }

    private static func cleanGeneratorVersion(_ ver: String?) -> String? {
        guard let ver else { return nil }
        let parts = ver.split(separator: ":").map(String.init)
        if parts.count == 2, !parts[0].isEmpty, parts[0] == parts[1] {
            return parts[0]
        }
        return ver
    }
}

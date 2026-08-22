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

/// Unified, `Sendable` model representing C2PA provenance validation results.
public struct ProvenanceReport: Sendable, Equatable {
    /// Identifier of the engine that produced this report.
    public var engineID: String
    /// Human-readable engine name.
    public var engineName: String
    /// Whether any C2PA content credentials were found for the asset.
    public var hasCredentials: Bool
    /// Wall-clock time spent producing this report (includes any bridge overhead).
    public var elapsed: Duration
    /// Engine-internal processing time (excluding bridge overhead), if reported by the engine.
    public var engineInternalElapsed: Duration?
    /// IANA media type of the asset, if known (e.g. "image/jpeg").
    public var mediaType: String?
    /// C2PA spec version reported by the engine, if any.
    public var specVersion: String?
    /// The active (most recent) manifest, if present.
    public var activeManifest: Manifest?
    /// Ingredient manifests referenced by the active manifest.
    public var ingredientManifests: [Manifest]
    /// The raw JSON the engine returned, preserved for debugging.
    public var rawJSON: String?

    public init(
        engineID: String,
        engineName: String,
        hasCredentials: Bool,
        elapsed: Duration,
        engineInternalElapsed: Duration? = nil,
        mediaType: String? = nil,
        specVersion: String? = nil,
        activeManifest: Manifest? = nil,
        ingredientManifests: [Manifest] = [],
        rawJSON: String? = nil
    ) {
        self.engineID = engineID
        self.engineName = engineName
        self.hasCredentials = hasCredentials
        self.elapsed = elapsed
        self.engineInternalElapsed = engineInternalElapsed
        self.mediaType = mediaType
        self.specVersion = specVersion
        self.activeManifest = activeManifest
        self.ingredientManifests = ingredientManifests
        self.rawJSON = rawJSON
    }

    /// A single, at-a-glance credential state for badging.
    public var badge: CredentialBadgeState {
        guard hasCredentials, let manifest = activeManifest else {
            return hasCredentials ? .invalid : .unsigned
        }
        return manifest.overallValidity
    }

    /// An empty "no credentials found" report for a given engine.
    public static func empty(
        engineID: String,
        engineName: String,
        elapsed: Duration,
        engineInternalElapsed: Duration? = nil,
        mediaType: String? = nil
    ) -> ProvenanceReport {
        ProvenanceReport(
            engineID: engineID,
            engineName: engineName,
            hasCredentials: false,
            elapsed: elapsed,
            engineInternalElapsed: engineInternalElapsed,
            mediaType: mediaType
        )
    }
}

/// The three-state credential badge.
public enum CredentialBadgeState: String, Sendable, Equatable {
    case signed
    case unsigned
    case invalid
}

/// A verifiable unit: a claim + assertions + signature about an asset.
public struct Manifest: Sendable, Equatable, Identifiable {
    public var id: String { label }
    /// Manifest label, unique within the manifest store.
    public var label: String
    /// Human title of the asset, if present.
    public var title: String?
    /// The declared format of the manifest, if present.
    public var format: String?
    /// Claim generator string (software that produced the claim).
    public var claimGenerator: String?
    /// Whether this is an update manifest.
    public var isUpdateManifest: Bool
    /// Signature / issuer information.
    public var signature: SignatureInfo?
    /// Assertions attached to this manifest.
    public var assertions: [Assertion]
    /// Validation statuses for this manifest.
    public var validationStatuses: [ValidationStatus]

    public init(
        label: String,
        title: String? = nil,
        format: String? = nil,
        claimGenerator: String? = nil,
        isUpdateManifest: Bool = false,
        signature: SignatureInfo? = nil,
        assertions: [Assertion] = [],
        validationStatuses: [ValidationStatus] = []
    ) {
        self.label = label
        self.title = title
        self.format = format
        self.claimGenerator = claimGenerator
        self.isUpdateManifest = isUpdateManifest
        self.signature = signature
        self.assertions = assertions
        self.validationStatuses = validationStatuses
    }

    /// Rolls validation statuses up into a single badge state.
    public var overallValidity: CredentialBadgeState {
        if validationStatuses.contains(where: { $0.severity == .error }) {
            return .invalid
        }
        return .signed
    }
}

/// Signature / issuer information for a manifest.
public struct SignatureInfo: Sendable, Equatable {
    /// Common name / issuer of the signing certificate.
    public var issuer: String?
    /// Signing algorithm, if reported (e.g. "es256").
    public var algorithm: String?
    /// Time the claim was signed / timestamped, if present.
    public var time: Date?
    /// A short human summary of the certificate chain, if available.
    public var certChainSummary: String?

    public init(
        issuer: String? = nil,
        algorithm: String? = nil,
        time: Date? = nil,
        certChainSummary: String? = nil
    ) {
        self.issuer = issuer
        self.algorithm = algorithm
        self.time = time
        self.certChainSummary = certChainSummary
    }
}

/// An assertion attached to a manifest.
public struct Assertion: Sendable, Equatable, Identifiable {
    public var id: String { label }
    /// The assertion label (e.g. "c2pa.actions", "c2pa.thumbnail.claim").
    public var label: String
    /// Coarse classification for grouping.
    public var kind: Kind
    /// A short human-readable summary of the assertion's payload.
    public var summary: String?

    public enum Kind: String, Sendable, Equatable {
        case actions
        case ingredient
        case thumbnail
        case aiTrainingMining
        case metadata
        case hash
        case other

        /// Classifies a C2PA assertion label into a coarse kind.
        public static func classify(label: String) -> Kind {
            let lowered = label.lowercased()
            if lowered.contains("action") { return .actions }
            if lowered.contains("ingredient") { return .ingredient }
            if lowered.contains("thumbnail") { return .thumbnail }
            if lowered.contains("training-mining") || lowered.contains("ai") {
                return .aiTrainingMining
            }
            if lowered.contains("hash") { return .hash }
            if lowered.contains("metadata") || lowered.contains("exif")
                || lowered.contains("xmp") {
                return .metadata
            }
            return .other
        }
    }

    public init(label: String, kind: Kind, summary: String? = nil) {
        self.label = label
        self.kind = kind
        self.summary = summary
    }
}

/// A validation status entry with a coarse severity.
public struct ValidationStatus: Sendable, Equatable, Identifiable {
    public var id: String { code + (url ?? "") }
    /// The C2PA validation status code (e.g. "claimSignature.validated").
    public var code: String
    /// Human explanation, if provided by the engine.
    public var explanation: String?
    /// The JUMBF URI the status refers to, if any.
    public var url: String?
    /// Coarse severity derived from the code.
    public var severity: Severity

    public enum Severity: String, Sendable, Equatable {
        case info
        case warning
        case error
    }

    public init(
        code: String,
        explanation: String? = nil,
        url: String? = nil,
        severity: Severity
    ) {
        self.code = code
        self.explanation = explanation
        self.url = url
        self.severity = severity
    }
}

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

/// Abstraction over a C2PA validation engine.
///
/// Implementations map their native output into `ProvenanceReport` so applications
/// depend only on this protocol and the unified model.
public protocol ProvenanceEngine: Sendable {
    /// Stable identifier (e.g. "credentio-native", "credentio").
    var id: String { get }
    /// Human-readable name (e.g. "Credentio Native (In-Process)").
    var displayName: String { get }

    /// Reads and validates the asset at `url`.
    ///
    /// - Returns: A `ProvenanceReport`. When the asset has no C2PA credentials,
    ///   returns a report with `hasCredentials == false` rather than throwing.
    /// - Throws: `ProvenanceError` only for genuine failures (unreadable file,
    ///   unsupported format, engine error).
    func read(url: URL) async throws -> ProvenanceReport
}

/// Errors surfaced by validation engines.
public enum ProvenanceError: Error, Sendable, Equatable {
    /// The file could not be read from disk.
    case unreadableFile(String)
    /// The asset's format is not supported by this engine.
    case unsupportedFormat(String)
    /// The engine failed while processing the asset.
    case engineFailure(String)
}

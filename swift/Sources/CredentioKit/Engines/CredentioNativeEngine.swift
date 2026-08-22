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

#if canImport(CredentioC)
import CredentioC

/// Thread-safe ownership wrapper for the C-ABI validator handle.
/// Automatically frees the native memory on deallocation without triggering actor deinit isolation rules.
private final class CredentioHandle: @unchecked Sendable {
    let ptr: OpaquePointer?

    init(ptr: OpaquePointer?) {
        self.ptr = ptr
    }

    deinit {
        if let ptr {
            cr_validator_free(ptr)
        }
    }
}
#endif

/// `ProvenanceEngine` backed by the Google Credentio C-ABI static library.
///
/// Runs directly in-process without spawning subprocesses, providing low-latency
/// validation and sub-millisecond core engine timing.
public actor CredentioNativeEngine: ProvenanceEngine {
    public nonisolated let id = "credentio-native"
    public nonisolated let displayName = "Credentio Native (In-Process)"

    public var claimSignerTrustPath: String?
    public var tsaTrustPath: String?
    public var skipTrustChecks: Bool

    #if canImport(CredentioC)
    private let handle: CredentioHandle?
    #endif

    public init(
        claimSignerTrustPath: String? = nil,
        tsaTrustPath: String? = nil,
        skipTrustChecks: Bool = true
    ) {
        self.claimSignerTrustPath = claimSignerTrustPath
        self.tsaTrustPath = tsaTrustPath
        self.skipTrustChecks = skipTrustChecks

        #if canImport(CredentioC)
        let claimPem = claimSignerTrustPath.flatMap { try? String(contentsOfFile: $0) }
        let tsaPem = tsaTrustPath.flatMap { try? String(contentsOfFile: $0) }

        let rawPtr = claimPem.withOptionalCString { claimCStr in
            tsaPem.withOptionalCString { tsaCStr in
                cr_validator_create(claimCStr, tsaCStr, skipTrustChecks ? 1 : 0)
            }
        }
        self.handle = CredentioHandle(ptr: rawPtr)
        #endif
    }

    /// Whether the native `CredentioC` library is compiled into the binary.
    public static var isAvailable: Bool {
        #if canImport(CredentioC)
        return true
        #else
        return false
        #endif
    }

    public func read(url: URL) async throws -> ProvenanceReport {
        let mediaType = SupportedFormats.mediaType(for: url)
        guard let format = mediaType else {
            throw ProvenanceError.unsupportedFormat(url.pathExtension)
        }

        #if canImport(CredentioC)
        let clock = ContinuousClock()
        let start = clock.now

        guard let validator = handle?.ptr else {
            throw ProvenanceError.engineFailure("Failed to initialize Credentio native validator")
        }

        var status: Int32 = 0
        let jsonPtr = url.path.withCString { pathCStr in
            format.withCString { formatCStr in
                cr_validate_file(validator, pathCStr, formatCStr, &status)
            }
        }

        let internalSeconds = cr_last_internal_seconds(validator)
        let lastErrorStr = String(cString: cr_last_error(validator))

        let elapsed = start.duration(to: clock.now)
        let internalDuration = Duration.seconds(internalSeconds)

        if status == CR_STATUS_NO_CREDENTIALS || jsonPtr == nil {
            if let jsonPtr { cr_string_free(jsonPtr) }
            return .empty(
                engineID: id,
                engineName: displayName,
                elapsed: elapsed,
                engineInternalElapsed: internalDuration,
                mediaType: format
            )
        }

        guard let jsonPtr else {
            throw ProvenanceError.engineFailure(
                lastErrorStr.isEmpty ? "Native validation failed with code \(status)" : lastErrorStr
            )
        }

        defer { cr_string_free(jsonPtr) }
        let jsonString = String(cString: jsonPtr)

        return CredentioCrjsonMapper.mapReport(
            json: jsonString,
            mediaType: format,
            elapsed: elapsed,
            engineInternalElapsed: internalDuration,
            engineID: id,
            engineName: displayName
        )
        #else
        // If native xcframework is not yet present, fall back to CLI engine
        let fallback = CredentioCLIEngine(
            claimSignerTrustPath: claimSignerTrustPath,
            tsaTrustPath: tsaTrustPath
        )
        return try await fallback.read(url: url)
        #endif
    }
}

private extension Optional where Wrapped == String {
    func withOptionalCString<R>(_ body: (UnsafePointer<CChar>?) throws -> R) rethrows -> R {
        if let self {
            return try self.withCString { try body($0) }
        } else {
            return try body(nil)
        }
    }
}

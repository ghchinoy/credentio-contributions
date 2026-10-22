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

private final class CredentioSignerHandle: @unchecked Sendable {
    let ptr: OpaquePointer?

    init(ptr: OpaquePointer?) {
        self.ptr = ptr
    }

    deinit {
        if let ptr {
            cr_signer_free(ptr)
        }
    }
}
#endif

/// Summary of an in-process C2PA asset signing operation.
public struct SignResult: Sendable, Equatable {
    public var outputURL: URL?
    public var signedData: Data?
    public var byteSize: Int
    public var mediaType: String?
    public var elapsed: Duration
    public var engineInternalElapsed: Duration?

    public init(
        outputURL: URL? = nil,
        signedData: Data? = nil,
        byteSize: Int,
        mediaType: String? = nil,
        elapsed: Duration,
        engineInternalElapsed: Duration? = nil
    ) {
        self.outputURL = outputURL
        self.signedData = signedData
        self.byteSize = byteSize
        self.mediaType = mediaType
        self.elapsed = elapsed
        self.engineInternalElapsed = engineInternalElapsed
    }
}

/// Actor-isolated C2PA manifest generator and asset signer backed by the Google Credentio C-ABI static library.
public actor CredentioSigner {
    #if canImport(CredentioC)
    private let handle: CredentioSignerHandle?
    #endif

    public init(
        claimSignerKeyPEM: String,
        claimSignerCertPEM: String,
        tsaKeyPEM: String? = nil,
        tsaCertPEM: String? = nil,
        generatorName: String = "CredentioKit",
        generatorVersion: String = "0.2.1"
    ) throws {
        #if canImport(CredentioC)
        let rawPtr = claimSignerKeyPEM.withCString { keyCStr in
            claimSignerCertPEM.withCString { certCStr in
                tsaKeyPEM.withOptionalSignerCString { tsaKeyCStr in
                    tsaCertPEM.withOptionalSignerCString { tsaCertCStr in
                        generatorName.withCString { genNameCStr in
                            generatorVersion.withCString { genVerCStr in
                                cr_signer_create(
                                    keyCStr,
                                    certCStr,
                                    tsaKeyCStr,
                                    tsaCertCStr,
                                    genNameCStr,
                                    genVerCStr
                                )
                            }
                        }
                    }
                }
            }
        }
        guard let rawPtr else {
            throw ProvenanceError.engineFailure(
                "Failed to initialize Credentio native signer (verify EC P-256 PKCS#8 key and certificate chain)"
            )
        }
        self.handle = CredentioSignerHandle(ptr: rawPtr)
        #else
        throw ProvenanceError.engineFailure("CredentioC native static framework is not available")
        #endif
    }

    /// Embeds and signs a C2PA manifest into `inputURL` and writes the signed asset to `outputURL`.
    public func sign(
        inputURL: URL,
        outputURL: URL,
        mediaType: String? = nil,
        digitalSourceType: String? = nil,
        customAssertionsJSON: String? = nil
    ) async throws -> SignResult {
        let resolvedFormat = mediaType ?? SupportedFormats.mediaType(for: inputURL)
        guard let format = resolvedFormat else {
            throw ProvenanceError.unsupportedFormat(inputURL.pathExtension)
        }

        #if canImport(CredentioC)
        guard let signer = handle?.ptr else {
            throw ProvenanceError.engineFailure("Credentio native signer is not initialized")
        }

        let clock = ContinuousClock()
        let start = clock.now

        let status = inputURL.path.withCString { inCStr in
            outputURL.path.withCString { outCStr in
                format.withCString { fmtCStr in
                    digitalSourceType.withOptionalSignerCString { dstCStr in
                        customAssertionsJSON.withOptionalSignerCString { assertionsCStr in
                            cr_sign_file(signer, inCStr, outCStr, fmtCStr, dstCStr, assertionsCStr)
                        }
                    }
                }
            }
        }

        let elapsed = start.duration(to: clock.now)
        let internalSeconds = cr_signer_last_internal_seconds(signer)
        let internalDuration = Duration.seconds(internalSeconds)

        if status != CR_STATUS_OK {
            let errMsg = String(cString: cr_signer_last_error(signer))
            throw ProvenanceError.engineFailure(
                errMsg.isEmpty ? "Native signing failed with status \(status)" : errMsg
            )
        }

        let fileSize = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
        return SignResult(
            outputURL: outputURL,
            byteSize: fileSize,
            mediaType: format,
            elapsed: elapsed,
            engineInternalElapsed: internalDuration
        )
        #else
        throw ProvenanceError.engineFailure("CredentioC native static framework is not available")
        #endif
    }

    /// Embeds and signs a C2PA manifest into in-memory `data` and returns the signed asset bytes.
    public func sign(
        data: Data,
        mediaType: String? = nil,
        digitalSourceType: String? = nil,
        customAssertionsJSON: String? = nil
    ) async throws -> SignResult {
        #if canImport(CredentioC)
        guard let signer = handle?.ptr else {
            throw ProvenanceError.engineFailure("Credentio native signer is not initialized")
        }

        let clock = ContinuousClock()
        let start = clock.now

        var outSize: Int = 0
        var outStatus: Int32 = 0

        let signedBufferPtr: UnsafeMutablePointer<UInt8>? = data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return nil
            }
            return mediaType.withOptionalSignerCString { fmtCStr in
                digitalSourceType.withOptionalSignerCString { dstCStr in
                    customAssertionsJSON.withOptionalSignerCString { assertionsCStr in
                        cr_sign_bytes(
                            signer,
                            baseAddress,
                            data.count,
                            fmtCStr,
                            dstCStr,
                            assertionsCStr,
                            &outSize,
                            &outStatus
                        )
                    }
                }
            }
        }

        let elapsed = start.duration(to: clock.now)
        let internalSeconds = cr_signer_last_internal_seconds(signer)
        let internalDuration = Duration.seconds(internalSeconds)

        guard let signedBufferPtr, outStatus == CR_STATUS_OK else {
            if let signedBufferPtr { cr_bytes_free(signedBufferPtr) }
            let errMsg = String(cString: cr_signer_last_error(signer))
            throw ProvenanceError.engineFailure(
                errMsg.isEmpty ? "Native in-memory signing failed with status \(outStatus)" : errMsg
            )
        }
        defer { cr_bytes_free(signedBufferPtr) }

        let signedData = Data(bytes: signedBufferPtr, count: outSize)
        return SignResult(
            signedData: signedData,
            byteSize: outSize,
            mediaType: mediaType,
            elapsed: elapsed,
            engineInternalElapsed: internalDuration
        )
        #else
        throw ProvenanceError.engineFailure("CredentioC native static framework is not available")
        #endif
    }
}

private extension Optional where Wrapped == String {
    func withOptionalSignerCString<R>(_ body: (UnsafePointer<CChar>?) throws -> R) rethrows -> R {
        if let self {
            return try self.withCString { try body($0) }
        } else {
            return try body(nil)
        }
    }
}

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

/// File-extension ↔ IANA media-type mapping for C2PA-supported media assets.
public enum SupportedFormats {
    /// Broad asset category.
    public enum Category: String, Sendable, CaseIterable {
        case image
        case video
        case audio
        case document
    }

    /// Extension (lowercase, no dot) → media type.
    public static let mediaTypesByExtension: [String: String] = [
        // Image
        "avif": "image/avif",
        "dng": "image/x-adobe-dng",
        "gif": "image/gif",
        "heic": "image/heic",
        "heif": "image/heif",
        "jpeg": "image/jpeg",
        "jpg": "image/jpeg",
        "png": "image/png",
        "tif": "image/tiff",
        "tiff": "image/tiff",
        "webp": "image/webp",
        // Video
        "avi": "video/x-msvideo",
        "mov": "video/quicktime",
        "mp4": "video/mp4",
        // Audio
        "m4a": "audio/mp4",
        "mp3": "audio/mpeg",
        "wav": "audio/wav",
        "flac": "audio/flac",
        // Document
        "pdf": "application/pdf",
        "docx":
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "pptx":
            "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        "xlsx":
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ]

    /// Category by extension (lowercase, no dot).
    public static let categoriesByExtension: [String: Category] = [
        "avif": .image, "dng": .image, "gif": .image, "heic": .image,
        "heif": .image, "jpeg": .image, "jpg": .image, "png": .image,
        "tif": .image, "tiff": .image, "webp": .image,
        "avi": .video, "mov": .video, "mp4": .video,
        "m4a": .audio, "mp3": .audio, "wav": .audio, "flac": .audio,
        "pdf": .document, "docx": .document, "pptx": .document, "xlsx": .document,
    ]

    /// Returns the media type for a URL, using magic byte inspection with extension fallback.
    public static func mediaType(for url: URL) -> String? {
        if let sniffed = sniffMediaType(for: url) {
            return sniffed
        }
        return mediaTypesByExtension[url.pathExtension.lowercased()]
    }

    /// Sniffs the true MIME type by inspecting the file's leading magic bytes.
    public static func sniffMediaType(for url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let headerData = try? handle.read(upToCount: 32), headerData.count >= 4 else {
            return nil
        }

        let bytes = [UInt8](headerData)

        // ID3 tag header (MP3 / MPEG audio container)
        if bytes.count >= 3, bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 { // "ID3"
            return "audio/mpeg"
        }

        // FLAC header
        if bytes.count >= 4, bytes[0] == 0x66, bytes[1] == 0x4C, bytes[2] == 0x61, bytes[3] == 0x43 { // "fLaC"
            return "audio/flac"
        }

        // JPEG header
        if bytes.count >= 3, bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
            return "image/jpeg"
        }

        // PNG header
        if bytes.count >= 8,
           bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47,
           bytes[4] == 0x0D, bytes[5] == 0x0A, bytes[6] == 0x1A, bytes[7] == 0x0A {
            return "image/png"
        }

        // GIF header
        if bytes.count >= 6,
           bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x38,
           (bytes[4] == 0x37 || bytes[4] == 0x39), bytes[5] == 0x61 {
            return "image/gif"
        }

        // PDF header
        if bytes.count >= 4, bytes[0] == 0x25, bytes[1] == 0x50, bytes[2] == 0x44, bytes[3] == 0x46 { // "%PDF"
            return "application/pdf"
        }

        // RIFF sub-type header
        if bytes.count >= 12,
           bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46 { // "RIFF"
            let form = String(bytes: bytes[8..<12], encoding: .ascii)
            switch form {
            case "WAVE": return "audio/wav"
            case "WEBP": return "image/webp"
            case "AVI ": return "video/x-msvideo"
            default: break
            }
        }

        // ISOBMFF / ftyp box
        if bytes.count >= 12,
           bytes[4] == 0x66, bytes[5] == 0x74, bytes[6] == 0x79, bytes[7] == 0x70 { // "ftyp"
            let majorBrand = String(bytes: bytes[8..<12], encoding: .ascii) ?? ""
            switch majorBrand {
            case "avif", "avis": return "image/avif"
            case "heic", "heix", "mif1": return "image/heic"
            case "mp41", "mp42", "isom", "M4V ": return "video/mp4"
            case "M4A ": return "audio/mp4"
            default: return "video/mp4"
            }
        }

        return nil
    }

    /// Returns the category for a URL, or `nil` if unsupported.
    public static func category(for url: URL) -> Category? {
        if let mime = mediaType(for: url) {
            if mime.starts(with: "image/") { return .image }
            if mime.starts(with: "video/") { return .video }
            if mime.starts(with: "audio/") { return .audio }
            if mime.starts(with: "application/") { return .document }
        }
        return categoriesByExtension[url.pathExtension.lowercased()]
    }

    /// Whether the URL's extension or magic bytes indicate a supported asset type.
    public static func isSupported(_ url: URL) -> Bool {
        mediaTypesByExtension[url.pathExtension.lowercased()] != nil || sniffMediaType(for: url) != nil
    }
}

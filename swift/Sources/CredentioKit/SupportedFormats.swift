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

    /// Returns the media type for a URL, or `nil` if unsupported.
    public static func mediaType(for url: URL) -> String? {
        mediaTypesByExtension[url.pathExtension.lowercased()]
    }

    /// Returns the category for a URL, or `nil` if unsupported.
    public static func category(for url: URL) -> Category? {
        categoriesByExtension[url.pathExtension.lowercased()]
    }

    /// Whether the URL's extension is a supported asset type.
    public static func isSupported(_ url: URL) -> Bool {
        mediaTypesByExtension[url.pathExtension.lowercased()] != nil
    }
}

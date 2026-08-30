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

/**
 * Sniffs the IANA media MIME type from the binary header magic bytes of a file buffer.
 *
 * Supported formats:
 * - JPEG (`image/jpeg`)
 * - PNG (`image/png`)
 * - GIF (`image/gif`)
 * - WebP (`image/webp`)
 * - AVIF (`image/avif`)
 * - HEIC (`image/heic`)
 * - MP4 (`video/mp4`)
 * - AVI (`video/x-msvideo`)
 * - MP3 (`audio/mpeg`)
 * - FLAC (`audio/flac`)
 * - WAV (`audio/wav`)
 * - M4A (`audio/mp4`)
 * - PDF (`application/pdf`)
 *
 * @param header Binary byte buffer containing at least the initial file header (e.g. 12+ bytes).
 * @returns Detected IANA media type string, or `undefined` if unknown or buffer too short.
 */
export function sniffMediaType(header: Uint8Array): string | undefined {
  if (!header || header.byteLength < 3) {
    return undefined;
  }

  // 1. MP3 with ID3v2 tag ("ID3")
  if (header.byteLength >= 3 && header[0] === 0x49 && header[1] === 0x44 && header[2] === 0x33) {
    return 'audio/mpeg';
  }

  // 2. JPEG (FF D8 FF)
  if (header[0] === 0xff && header[1] === 0xd8 && header[2] === 0xff) {
    return 'image/jpeg';
  }

  // 3. FLAC ("fLaC")
  if (
    header.byteLength >= 4 &&
    header[0] === 0x66 &&
    header[1] === 0x4c &&
    header[2] === 0x61 &&
    header[3] === 0x43
  ) {
    return 'audio/flac';
  }

  // 4. PDF ("%PDF")
  if (
    header.byteLength >= 4 &&
    header[0] === 0x25 &&
    header[1] === 0x50 &&
    header[2] === 0x44 &&
    header[3] === 0x46
  ) {
    return 'application/pdf';
  }

  // 5. GIF ("GIF87a" or "GIF89a")
  if (
    header.byteLength >= 6 &&
    header[0] === 0x47 &&
    header[1] === 0x49 &&
    header[2] === 0x46 &&
    header[3] === 0x38 &&
    (header[4] === 0x37 || header[4] === 0x39) &&
    header[5] === 0x61
  ) {
    return 'image/gif';
  }

  // 6. PNG (89 50 4E 47 0D 0A 1A 0A)
  if (
    header.byteLength >= 8 &&
    header[0] === 0x89 &&
    header[1] === 0x50 &&
    header[2] === 0x4e &&
    header[3] === 0x47 &&
    header[4] === 0x0d &&
    header[5] === 0x0a &&
    header[6] === 0x1a &&
    header[7] === 0x0a
  ) {
    return 'image/png';
  }

  // 7. RIFF container (WAV, WEBP, AVI)
  if (
    header.byteLength >= 12 &&
    header[0] === 0x52 &&
    header[1] === 0x49 &&
    header[2] === 0x46 &&
    header[3] === 0x46
  ) {
    const subType = String.fromCharCode(header[8], header[9], header[10], header[11]);
    if (subType === 'WAVE') return 'audio/wav';
    if (subType === 'WEBP') return 'image/webp';
    if (subType === 'AVI ') return 'video/x-msvideo';
  }

  // 8. ISOBMFF container (MP4, AVIF, HEIC, M4A)
  if (
    header.byteLength >= 12 &&
    header[4] === 0x66 &&
    header[5] === 0x74 &&
    header[6] === 0x79 &&
    header[7] === 0x70
  ) {
    const majorBrand = String.fromCharCode(header[8], header[9], header[10], header[11]);
    if (majorBrand === 'avif' || majorBrand === 'avis') {
      return 'image/avif';
    }
    if (
      majorBrand === 'heic' ||
      majorBrand === 'heix' ||
      majorBrand === 'mif1' ||
      majorBrand === 'msf1'
    ) {
      return 'image/heic';
    }
    if (majorBrand === 'M4A ') {
      return 'audio/mp4';
    }
    return 'video/mp4';
  }

  return undefined;
}

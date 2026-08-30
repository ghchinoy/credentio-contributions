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

import { describe, expect, it } from 'vitest';
import { sniffMediaType } from '../src/sniff.js';

describe('sniffMediaType Magic Byte Detection', () => {
  it('detects JPEG images', () => {
    const header = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]);
    expect(sniffMediaType(header)).toBe('image/jpeg');
  });

  it('detects PNG images', () => {
    const header = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00]);
    expect(sniffMediaType(header)).toBe('image/png');
  });

  it('detects GIF images', () => {
    const gif87 = new Uint8Array([0x47, 0x49, 0x46, 0x38, 0x37, 0x61, 0x00, 0x00]);
    const gif89 = new Uint8Array([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x00, 0x00]);
    expect(sniffMediaType(gif87)).toBe('image/gif');
    expect(sniffMediaType(gif89)).toBe('image/gif');
  });

  it('detects PDF documents', () => {
    const header = new TextEncoder().encode('%PDF-1.7\n%...');
    expect(sniffMediaType(header)).toBe('application/pdf');
  });

  it('detects MP3 audio with ID3 header', () => {
    const header = new Uint8Array([0x49, 0x44, 0x33, 0x03, 0x00, 0x00]);
    expect(sniffMediaType(header)).toBe('audio/mpeg');
  });

  it('detects FLAC audio', () => {
    const header = new Uint8Array([0x66, 0x4c, 0x61, 0x43, 0x00, 0x00]);
    expect(sniffMediaType(header)).toBe('audio/flac');
  });

  it('detects RIFF containers (WAV, WEBP, AVI)', () => {
    const wav = new TextEncoder().encode('RIFF\x24\x00\x00\x00WAVEfmt ');
    const webp = new TextEncoder().encode('RIFF\x24\x00\x00\x00WEBPVP8 ');
    const avi = new TextEncoder().encode('RIFF\x24\x00\x00\x00AVI LIST');

    expect(sniffMediaType(wav)).toBe('audio/wav');
    expect(sniffMediaType(webp)).toBe('image/webp');
    expect(sniffMediaType(avi)).toBe('video/x-msvideo');
  });

  it('detects ISOBMFF containers (MP4, AVIF, HEIC, M4A)', () => {
    const mp4 = new TextEncoder().encode('\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00');
    const avif = new TextEncoder().encode('\x00\x00\x00\x18ftypavif\x00\x00\x00\x00');
    const heic = new TextEncoder().encode('\x00\x00\x00\x18ftypheic\x00\x00\x00\x00');
    const m4a = new TextEncoder().encode('\x00\x00\x00\x18ftypM4A \x00\x00\x00\x00');

    expect(sniffMediaType(mp4)).toBe('video/mp4');
    expect(sniffMediaType(avif)).toBe('image/avif');
    expect(sniffMediaType(heic)).toBe('image/heic');
    expect(sniffMediaType(m4a)).toBe('audio/mp4');
  });

  it('returns undefined for unknown or short buffers', () => {
    expect(sniffMediaType(new Uint8Array([]))).toBeUndefined();
    expect(sniffMediaType(new Uint8Array([0x00, 0x01]))).toBeUndefined();
    expect(sniffMediaType(new Uint8Array([0x00, 0x01, 0x02, 0x03]))).toBeUndefined();
  });
});

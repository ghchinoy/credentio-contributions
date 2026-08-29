---
title: C-ABI Architecture
description: Deep dive into the FFI bridge, memory management, and monolithic shared library compilation.
---

Google Credentio is authored in C++20. To provide seamless bindings for Python and Go without binding directly to C++ standard library templates, Protocol Buffers, or Abseil data structures, this project implements an intermediate `extern "C"` Application Binary Interface (C-ABI).

---

## 1. The C-ABI Interface (`native/credentio_c.h`)

The C-ABI exposes an opaque pointer model:

```c
typedef struct cr_validator cr_validator;

CR_EXPORT cr_validator* cr_validator_create(
    const char* claim_signer_trust_pem,
    const char* tsa_trust_pem,
    int skip_trust_checks);

CR_EXPORT void cr_validator_free(cr_validator* validator);

CR_EXPORT char* cr_validate_file(
    cr_validator* validator,
    const char* file_path,
    const char* media_type,
    int* out_status);

CR_EXPORT char* cr_validate_bytes(
    cr_validator* validator,
    const uint8_t* bytes,
    size_t count,
    const char* media_type,
    int* out_status);

CR_EXPORT const char* cr_last_error(cr_validator* validator);
CR_EXPORT double cr_last_internal_seconds(cr_validator* validator);
CR_EXPORT void cr_string_free(char* str);
```

---

## 2. Memory Ownership & Safety Rules

1. **Validator Handle:** Managed via `cr_validator_create` and freed via `cr_validator_free`.
   - In Python, `Validator.__exit__` or `__del__` invokes `cr_validator_free`.
   - In Go, `Validator.Close()` invokes `C.cr_validator_free`.
2. **Result String Allocation:** `cr_validate_file` and `cr_validate_bytes` return heap-allocated `malloc()` strings containing UTF-8 formatted crJSON.
   - The caller copies the string into Python/Go memory space, then immediately invokes `cr_string_free(ptr)`.
3. **Error Strings:** `cr_last_error` returns a `const char*` pointer into internal C++ `std::string` memory that remains valid until the next method invocation on that validator.

---

## 3. High-Resolution Core Timing

To enable fair benchmarking against other validators, the C-ABI measures engine-internal execution time using monotonic clocks:

```cpp
const auto start_time = std::chrono::high_resolution_clock::now();
const auto result_status = v->validator->Validate(reader, media_type_opt);
const auto end_time = std::chrono::high_resolution_clock::now();

const std::chrono::duration<double> diff = end_time - start_time;
v->last_internal_seconds = diff.count();
```

This isolates the raw C++ cryptographic validation time from file I/O, Python/Go runtime overhead, and garbage collection pauses.

---

## 4. Container Sniffing & Format Resolution

Google Credentio relies on format extractors (such as `Id3Extractor` for MPEG audio, `RiffExtractor` for WAV/WebP, and `IsobmffExtractor` for MP4/ISOBMFF). When an asset is named with a mismatched extension (for example, an MP3 stream saved with a `.wav` extension), relying only on file extension causes extractor dispatch to fail.

To ensure resilience, the C-ABI layer and language bindings inspect the leading 32 header bytes before falling back to filename extension:
- `49 44 33` (`ID3`) $\to$ `audio/mpeg`
- `66 4C 61 43` (`fLaC`) $\to$ `audio/flac`
- `52 49 46 46 .... 57 41 56 45` (`RIFF...WAVE`) $\to$ `audio/wav`
- `52 49 46 46 .... 57 45 42 50` (`RIFF...WEBP`) $\to$ `image/webp`
- `FF D8 FF` $\to$ `image/jpeg`
- `89 50 4E 47` $\to$ `image/png`
- `25 50 44 46` $\to$ `application/pdf`
- `.... 66 74 79 70` (`ftyp`) $\to$ `video/mp4`, `audio/mp4`, `image/heic`, `image/avif`

---

## 5. Monolithic Shared Library Compilation

The Bazel build target:

```python
cc_binary(
    name = "libcredentio_c",
    deps = [":credentio_c"],
    linkshared = True,
)
```

By specifying `linkshared = True` and setting `alwayslink = True` on `credentio_c`, Bazel's linker automatically pulls in and resolves all transitive static dependencies:
- **BoringSSL:** Cryptographic primitives and X.509 parsing
- **Google Tink:** Digital signature verification
- **Riegeli:** Zero-copy backwards-seeking I/O readers
- **Abseil & Protobuf:** Core data structures and message serialization
- **nlohmann_json:** JSON construction and dumping

The resulting `libcredentio_c.dylib` (macOS) or `libcredentio_c.so` (Linux) is completely self-contained and requires no external C++ runtime dependencies beyond `libc++`.

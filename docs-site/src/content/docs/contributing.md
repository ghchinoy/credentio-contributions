---
title: Contributing & Upstreaming
description: How to contribute to this project and path toward upstreaming bindings to Google Credentio.
---

We welcome contributions, bug reports, and optimizations for the Python, Go, and Swift Credentio bindings!

Please review our root [Contributing Guidelines](https://github.com/ghchinoy/credentio-contributions/blob/main/CONTRIBUTING.md) and [Code of Conduct](https://github.com/ghchinoy/credentio-contributions/blob/main/CODE_OF_CONDUCT.md).

---

## 1. Development Workflow

### Building Native Libraries
```bash
make build-lib    # For Python and Go
make build-swift  # For Swift (macOS only)
```

### Running Tests
```bash
# Run test suites:
make python-test  # Python (pytest)
make go-test      # Go (go test)
make swift-test   # Swift (swift test)
```

---

## 2. Upstreaming to Google Credentio

Google Credentio is maintained at [mediaprovenance.googlesource.com/credentio](https://mediaprovenance.googlesource.com/credentio/).

The C-ABI layer (`native/credentio_c.{h,cc}`) was engineered to cleanly drop directly into Credentio's upstream repository under a `bindings/` or `bindings_c/` directory.

### Structure for Upstream Consideration:
- `bindings_c/credentio_c.h` — Pure C header with default visibility exports.
- `bindings_c/credentio_c.cc` — In-process C++ bridge with `CFileReader` and `StringReader`.
- `bindings_c/BUILD` — Standard Bazel rules (`cc_library` and `cc_binary(linkshared=True)`).

---

## 3. License & Disclaimer

This project is licensed under the **Apache License, Version 2.0**.

### Disclaimer
*This project is an open-source community contribution and is not an officially supported Google product.*

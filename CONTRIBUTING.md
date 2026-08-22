# Contributing to Credentio Contributions

Thank you for your interest in contributing to the Python, Go, and Swift bindings for Google Credentio!

---

## 1. Code of Conduct

All contributors and maintainers are expected to follow our [Code of Conduct](CODE_OF_CONDUCT.md).

---

## 2. Getting Started

### Local Development Setup
1. Clone Google Credentio and check out the validated commit:
   ```bash
   git clone https://mediaprovenance.googlesource.com/credentio
   cd credentio
   git checkout 4ac69fc58256d3871e765f615254373e19e250e9
   ```
2. Clone this repository:
   ```bash
   git clone https://github.com/google/credentio-contributions.git
   cd credentio-contributions
   ```
3. Compile the native libraries:
   ```bash
   make build-lib    # For Python and Go
   make build-swift  # For Swift (macOS only)
   ```

---

## 3. Running Tests

Before submitting a pull request, run the test suites across all languages:

```bash
make python-test  # Run pytest
make go-test      # Run go test
make swift-test   # Run swift test (on macOS)
```

---

## 4. Submitting Pull Requests

1. Fork the repository and create your feature branch: `git checkout -b feature/my-feature`.
2. Commit your changes with clear, descriptive commit messages.
3. Ensure all tests pass.
4. Open a pull request against the `main` branch.

---

## 5. Upstreaming to Google Credentio

The C-ABI layer (`native/credentio_c.{h,cc}`) and language bindings in this repository are designed to be proposed upstream to [Google Credentio](https://mediaprovenance.googlesource.com/credentio/) as official bindings.

If you are contributing changes to the core C-ABI, please ensure that changes preserve C-linkage compatibility and do not leak C++ standard library types across the C boundary.

---

## 6. License

By contributing, you agree that your contributions will be licensed under the **Apache License, Version 2.0**.

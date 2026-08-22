# 0001 — Shared C-ABI strategy for Python and Go bindings

- Status: Accepted
- Date: 2026-08-22

## Context

Google Credentio is a C++20 library built with Bazel. We need idiomatic, high-performance bindings for both Python and Go to enable developers to validate C2PA Content Credentials across server-side and data-science workflows.

Directly wrapping C++ in Python (e.g. pybind11) and Go (swig or complex cgo C++ wrappers) introduces multiple independent maintenance surfaces and complex toolchain couplings.

## Decision

1. Use a single, unified `extern "C"` ABI bridge (`native/credentio_c.{h,cc}`) as the shared FFI foundation for both Python and Go.
2. Build a monolithic dynamic shared library (`libcredentio_c.dylib` / `libcredentio_c.so`) using Bazel's `cc_binary(linkshared = True)`.
3. In Python, consume the shared library via `cffi` and parse output into dataclasses.
4. In Go, consume the shared library via `cgo` and parse output into Go structs.
5. Provide both `ValidateFile` (file-path based) and `ValidateBytes` (in-memory bytes based) validation methods.

## Consequences

- Both language bindings share a single C-ABI implementation.
- Future enhancements to Credentio validation semantics or crJSON formatting propagate automatically to both Python and Go.
- In-process execution avoids subprocess startup overhead for both languages.

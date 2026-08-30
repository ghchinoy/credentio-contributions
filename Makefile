.PHONY: help build-lib build-swift build-wasm fetch-lib check-drift python-install python-test go-test swift-test wasm-install wasm-build wasm-test test docs-install docs-serve docs-build clean

help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-18s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build-lib: ## Build native libcredentio_c shared library (for Python & Go)
	@echo "Building libcredentio_c shared library..."
	./scripts/build-shared-lib.sh

build-swift: ## Build native CredentioC.xcframework static library (for Swift)
	@echo "Building CredentioC static xcframework for Swift..."
	./scripts/build-swift-xcframework.sh

build-wasm: ## Build native WebAssembly binary (credentio.wasm & credentio.js)
	@echo "Building WebAssembly binary via Emscripten..."
	./scripts/build-wasm.sh

fetch-lib: ## Download prebuilt native library from GitHub Releases for Go & Python
	@echo "Downloading prebuilt libcredentio_c binary..."
	./scripts/fetch-prebuilt-lib.sh

check-drift: ## Check if upstream Google Credentio has drifted from .credentio-pin
	@echo "Checking for upstream Credentio drift..."
	./scripts/check-credentio-drift.sh

python-install: ## Install Python credentio package in editable mode
	@echo "Installing Python package..."
	cd python && python3 -m pip install -e ".[dev]"

python-test: ## Run Python test suite (pytest)
	@echo "Running Python tests..."
	cd python && python3 -m pip install -e ".[dev]" --quiet && python3 -m pytest

go-test: ## Run Go test suite (go test)
	@echo "Running Go tests..."
	cd go && CGO_ENABLED=1 go test -v ./...

swift-test: ## Run Swift unit tests (swift test)
	@echo "Running Swift tests..."
	cd swift && swift test

wasm-install: ## Install TypeScript WASM package dependencies (npm)
	@echo "Installing WASM package dependencies..."
	cd wasm && npm install

wasm-build: wasm-install ## Compile TypeScript WASM package (tsc / build)
	@echo "Building TypeScript WASM package..."
	cd wasm && npm run build

wasm-test: wasm-build ## Run TypeScript WASM test suite (npm test)
	@echo "Running TypeScript WASM tests..."
	cd wasm && npm test

test: python-test go-test wasm-test ## Run Python, Go, and WASM test suites

docs-install: ## Install documentation site dependencies (npm)
	@echo "Installing documentation dependencies..."
	cd docs-site && npm install

docs-serve: docs-install ## Launch Astro Starlight local documentation dev server
	@echo "Starting documentation server..."
	cd docs-site && npm run dev

docs-build: docs-install ## Build static documentation site (Astro Starlight)
	@echo "Building documentation site..."
	cd docs-site && npm run build

clean: ## Clean build artifacts
	@echo "Cleaning artifacts..."
	rm -rf native/libcredentio_c.* python/src/credentio/lib python/dist python/build python/*.egg-info go/lib docs-site/dist docs-site/.astro swift/.build swift/CredentioC.xcframework wasm/dist wasm/lib wasm/node_modules wasm/.turbo docs-site/public/wasm
	find . -type d -name "__pycache__" -exec rm -rf {} +
	@echo "Clean complete."

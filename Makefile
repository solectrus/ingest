.PHONY: help build run test install clean format format-check
.DEFAULT_GOAL := help

# Show available targets
help:
	@echo "Available targets:"
	@echo "  make install        - Install dependencies"
	@echo "  make build          - Build release binary"
	@echo "  make run            - Run in development mode"
	@echo "  make test           - Run tests"
	@echo "  make clean          - Clean build artifacts"
	@echo "  make format         - Format code"
	@echo "  make format-check   - Check code formatting"

# Build the Crystal application
build:
	mkdir -p bin
	crystal build src/ingest.cr --release -o bin/ingest

# Run in development mode (loads .env automatically)
run:
	crystal run src/ingest.cr

# Run tests
test:
	crystal spec

# Install dependencies
install:
	shards install

# Clean build artifacts
clean:
	rm -rf bin/ingest lib/ .crystal/

# Format code
format:
	crystal tool format

# Check formatting
format-check:
	crystal tool format --check

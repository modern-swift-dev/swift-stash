SHELL := /bin/bash

SCHEME ?= SwiftStash
IOS_DESTINATION ?= platform=iOS Simulator,name=iPhone 17 Pro,OS=latest
TVOS_DESTINATION ?= platform=tvOS Simulator,name=Apple TV 4K (3rd generation),OS=latest
WATCHOS_DESTINATION ?= platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=latest
VISIONOS_DESTINATION ?= platform=visionOS Simulator,name=Apple Vision Pro,OS=latest

.PHONY: setup lint format documentation site-setup site-preview site-validate \
	site-build test test-swift test-linux test-macos test-ios test-tvos \
	test-watchos test-visionos test-apple test-all

setup:

	brew bundle install
	brew upgrade
	brew cleanup
	brew autoremove
	mint bootstrap
	lefthook install

lint:

	mint run --no-install realm/SwiftLint  --config .swiftlint.yml --quiet

format:

	mint run --no-install nicklockwood/SwiftFormat . --config .swiftformat --quiet
	mint run --no-install realm/SwiftLint  --config .swiftlint.yml --fix --quiet

documentation:

	bash Scripts/build-documentation.sh

site-setup:
	npm --prefix Website ci

site-preview:
	node Scripts/preview-site.mjs

site-validate:
	npm --prefix Website run check
	npm --prefix Website run build
	test -f Website/dist/index.html
	node Scripts/check-links.mjs docs

site-build:
	bash Scripts/build-site.sh

test-linux:
	docker run \
		--rm \
		-v "$(PWD):/workspace" \
		-w /workspace \
		swift:6.3 \
		bash -c 'swift test --scratch-path .build/linux'

test-macos: test-swift

test-ios:
	set -o pipefail && \
	xcodebuild test \
		-scheme "$(SCHEME)" \
		-destination "$(IOS_DESTINATION)" | mint run --no-install cpisciotta/xcbeautify -q

test-swift:
	set -o pipefail && \
	swift test | mint run --no-install cpisciotta/xcbeautify -q

test: test-swift

test-tvos:
	set -o pipefail && \
	xcodebuild test \
		-scheme "$(SCHEME)" \
		-destination "$(TVOS_DESTINATION)" | mint run --no-install cpisciotta/xcbeautify -q

test-watchos:
	set -o pipefail && \
	xcodebuild test \
		-scheme "$(SCHEME)" \
		-destination "$(WATCHOS_DESTINATION)" | mint run --no-install cpisciotta/xcbeautify -q

test-visionos:
	set -o pipefail && \
	xcodebuild test \
		-scheme "$(SCHEME)" \
		-destination "$(VISIONOS_DESTINATION)" | mint run --no-install cpisciotta/xcbeautify -q

test-apple: test-macos test-ios test-tvos test-watchos test-visionos

test-all: test-apple test-linux

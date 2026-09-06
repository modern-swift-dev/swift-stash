# Contributing

## Development

Install the contributor tools and Git hooks with:

```sh
make setup
```

This installs the Homebrew and Mint dependencies declared by the project and configures [Lefthook](https://github.com/evilmartians/lefthook). Lefthook runs the repository's configured checks from Git hooks so formatting and lint issues are caught before changes are committed.

The `Makefile` provides the common development commands:

```sh
make test          # Run the Swift package tests
make lint          # Check the Swift sources with SwiftLint
make format        # Apply SwiftFormat and SwiftLint fixes
make documentation # Build the API documentation
make test-all      # Test all supported Apple platforms and Linux
```

For a direct SwiftPM test run, use:

```sh
swift test
```

## Publishing the documentation site

Guides and examples live in [Documentation/Site](Documentation/Site). The [central documentation repository](https://github.com/modern-swift-dev/docs) owns the shared Astro theme, builds the guides and DocC API reference, and publishes them daily. For local builds and previews, follow the [docs README](https://github.com/modern-swift-dev/docs/blob/main/README.md).

Keep Markdown guides, example source, and Swift documentation comments in this module. Publish a GitHub release to update the version and release information on the next daily build. Commit documentation sources only.

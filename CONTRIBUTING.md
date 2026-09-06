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
make site-setup    # Install the locked website dependencies
make site-validate # Type-check and build the Astro site
make site-build    # Replace .build/site/ with the Astro and DocC output
make site-preview  # Serve the assembled .build/site/ directory locally
make test-all      # Test all supported Apple platforms and Linux
```

For a direct SwiftPM test run, use:

```sh
swift test
```

## Publishing the documentation site

The documentation sources remain in this repository. The [central documentation repository](https://github.com/modern-swift-dev/docs) builds and publishes them daily at [the module documentation site](https://modern-swift-dev.github.io/docs/swift-stash/). Publish a GitHub release to update the release information on the next scheduled build; publishing is configured in the central repository.

To build and review documentation locally:

```sh
make site-setup
make site-build
make site-validate
make site-preview
```

The build fetches the latest published release, builds the Astro pages and static DocC reference, and checks internal links. Generated HTML is written to `.build/site/` and is ignored by Git. Commit documentation source changes only.

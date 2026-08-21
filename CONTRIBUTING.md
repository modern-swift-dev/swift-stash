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
make site-build    # Replace docs/ with the Astro and DocC output
make site-preview  # Serve the assembled docs/ directory locally
make test-all      # Test all supported Apple platforms and Linux
```

For a direct SwiftPM test run, use:

```sh
swift test
```

## Publishing the documentation site

The Astro source is in `Website/`. `docs/` contains generated files for GitHub Pages and is committed so maintainers can review every site update.

For each release:

1. Publish the GitHub release.
2. Run `make site-setup` and `make site-build` from the repository root.
3. Confirm that the release card shows the published version and review the generated Astro and DocC changes in `docs/`.
4. Run `make site-preview` for a final local check, then commit `docs/` with the source changes.

The build stops if GitHub does not return a valid latest published release. It also checks internal links before replacing `docs/`.

GitHub Pages needs one manual repository setting. In **Settings > Pages**, choose **Deploy from a branch**, select `main`, select `/docs`, and save. GitHub documents these steps in [Configuring a publishing source for your GitHub Pages site](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site). The build does not change this remote setting.

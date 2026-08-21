# SwiftStash examples

Each directory is a standalone executable Swift package that uses the local SwiftStash checkout.

```sh
swift run --package-path Examples/memory-cache
swift run --package-path Examples/disk-cache
swift run --package-path Examples/custom-serializer
```

When copying an example into another repository, replace the local package dependency in its `Package.swift` with the Git URL and version requirement shown in the project README.

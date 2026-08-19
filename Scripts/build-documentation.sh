#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output_directory="$repository_root/.build/documentation"
derived_data_directory="$output_directory/DerivedData"
archive_directory="$output_directory/archives"
archive_path="$output_directory/SwiftStash-Documentation.zip"
expected_archive="SwiftStash.doccarchive"

mkdir -p "$output_directory"
rm -rf "$archive_directory"
rm -f "$archive_path"
mkdir -p "$archive_directory"

xcodebuild docbuild \
    -scheme SwiftStash \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$derived_data_directory"

archive_source="$(find "$derived_data_directory/Build/Products" -type d -name "$expected_archive" -print -quit)"
if [[ -z "$archive_source" ]]; then
    echo "Expected documentation archive was not generated: $expected_archive" >&2
    exit 1
fi
cp -R "$archive_source" "$archive_directory/$expected_archive"

(
    cd "$archive_directory"
    zip -qry "$archive_path" "$expected_archive"
)

unzip -tq "$archive_path" >/dev/null
echo "Created $archive_path"

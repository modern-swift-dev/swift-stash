#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
website_directory="$repository_root/Website"
output_directory="$repository_root/docs"
staging_directory="$repository_root/.build/site-staging"
expected_output_directory="$repository_root/docs"

if [[ "$output_directory" != "$expected_output_directory" ]]; then
    echo "Refusing to replace unexpected output directory: $output_directory" >&2
    exit 1
fi

rm -rf "$staging_directory"
mkdir -p "$staging_directory"

npm --prefix "$website_directory" run check
npm --prefix "$website_directory" run build
cp -R "$website_directory/dist/." "$staging_directory"

swift package \
    --allow-writing-to-directory "$staging_directory/api" \
    generate-documentation \
    --target SwiftStash \
    --disable-indexing \
    --transform-for-static-hosting \
    --hosting-base-path swift-stash/api \
    --output-path "$staging_directory/api"

touch "$staging_directory/.nojekyll"
node "$repository_root/Scripts/check-links.mjs" "$staging_directory"

rm -rf "$output_directory"
mkdir -p "$output_directory"
cp -R "$staging_directory/." "$output_directory"
rm -rf "$staging_directory"

echo "Built the GitHub Pages site at $output_directory"

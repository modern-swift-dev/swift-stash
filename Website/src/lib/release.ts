export interface Release {
  version: string;
  installationVersion: string;
  publishedAt: string;
  notesURL: string;
}

interface GitHubRelease {
  draft: boolean;
  prerelease: boolean;
  tag_name: string;
  published_at: string;
  html_url: string;
}

const releasesURL = "https://api.github.com/repos/modern-swift-dev/swift-stash/releases/latest";

function isGitHubRelease(value: unknown): value is GitHubRelease {
  if (typeof value !== "object" || value === null) {
    return false;
  }

  const release = value as Record<string, unknown>;
  return typeof release.draft === "boolean"
    && typeof release.prerelease === "boolean"
    && typeof release.tag_name === "string"
    && typeof release.published_at === "string"
    && typeof release.html_url === "string";
}

function installationVersion(tag: string): string {
  return tag.startsWith("v") ? tag.slice(1) : tag;
}

async function fetchLatestRelease(): Promise<Release> {
  let response: Response;
  const headers = new Headers({
    Accept: "application/vnd.github+json",
    "User-Agent": "swift-stash-static-site",
    "X-GitHub-Api-Version": "2022-11-28"
  });
  const githubToken = import.meta.env.GITHUB_TOKEN;
  if (githubToken) {
    headers.set("Authorization", `Bearer ${githubToken}`);
  }

  try {
    response = await fetch(releasesURL, {
      headers,
      signal: AbortSignal.timeout(10_000)
    });
  } catch (error) {
    throw new Error(`Could not fetch the SwiftStash releases from GitHub: ${String(error)}`);
  }

  if (!response.ok) {
    throw new Error(`Could not fetch the SwiftStash releases from GitHub: HTTP ${response.status}.`);
  }

  let payload: unknown;
  try {
    payload = await response.json();
  } catch (error) {
    throw new Error(`GitHub returned malformed release data for SwiftStash: ${String(error)}`);
  }
  if (!isGitHubRelease(payload)) {
    throw new Error("GitHub returned an invalid releases response for SwiftStash.");
  }

  if (payload.draft || payload.prerelease) {
    throw new Error("GitHub returned no published, non-prerelease SwiftStash release.");
  }

  const version = payload.tag_name.trim();
  const versionForInstallation = installationVersion(version);
  const date = new Date(payload.published_at);
  let notesURL: URL;
  try {
    notesURL = new URL(payload.html_url);
  } catch {
    throw new Error("GitHub returned an invalid release-notes URL for SwiftStash.");
  }
  if (
    !version
    || !versionForInstallation
    || Number.isNaN(date.getTime())
    || notesURL.protocol !== "https:"
    || notesURL.hostname !== "github.com"
  ) {
    throw new Error("GitHub returned incomplete release data for SwiftStash.");
  }

  return {
    version,
    installationVersion: versionForInstallation,
    publishedAt: payload.published_at,
    notesURL: notesURL.href
  };
}

let latestReleasePromise: Promise<Release> | undefined;

export function getLatestRelease(): Promise<Release> {
  latestReleasePromise ??= fetchLatestRelease();
  return latestReleasePromise;
}

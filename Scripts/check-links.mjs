import { existsSync, lstatSync, readdirSync, readFileSync } from 'node:fs';
import { extname, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const siteDirectory = resolve(process.argv[2] ?? fileURLToPath(new URL('../docs', import.meta.url)));
const siteBasePath = '/swift-stash';

if (!existsSync(siteDirectory) || !lstatSync(siteDirectory).isDirectory()) {
  throw new Error(`Site directory does not exist: ${siteDirectory}`);
}

function filesBelow(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const path = join(directory, entry.name);
    return entry.isDirectory() ? filesBelow(path) : [path];
  });
}

function candidatePaths(pathname) {
  const relativePath = pathname.replace(/^\/+/, '');
  const directPath = join(siteDirectory, relativePath);
  return extname(directPath)
    ? [directPath]
    : [directPath, join(directPath, 'index.html'), `${directPath}.html`];
}

function localTarget(rawValue) {
  if (
    rawValue.startsWith('data:') ||
    rawValue.startsWith('mailto:') ||
    rawValue.startsWith('tel:') ||
    rawValue.startsWith('javascript:') ||
    rawValue.startsWith('//')
  ) {
    return undefined;
  }

  let url;
  try {
    url = new URL(rawValue, 'https://modern-swift-dev.github.io/swift-stash/');
  } catch {
    return { error: `invalid URL: ${rawValue}` };
  }

  if (url.origin !== 'https://modern-swift-dev.github.io') {
    return undefined;
  }

  if (url.pathname !== siteBasePath && !url.pathname.startsWith(`${siteBasePath}/`)) {
    return { error: `path escapes ${siteBasePath}: ${rawValue}` };
  }

  let decodedPath;
  try {
    decodedPath = decodeURIComponent(url.pathname.slice(siteBasePath.length));
  } catch {
    return { error: `invalid URL encoding: ${rawValue}` };
  }

  const resolvedCandidates = candidatePaths(decodedPath);
  const directPath = resolvedCandidates[0];
  const contained = directPath === siteDirectory || directPath.startsWith(`${siteDirectory}${sep}`);
  if (!contained) {
    return { error: `path escapes site directory: ${rawValue}` };
  }

  return { candidates: resolvedCandidates, fragment: url.hash, rawValue };
}

function hasFragment(htmlFile, fragment) {
  if (!fragment) return true;
  let decodedFragment;
  try {
    decodedFragment = decodeURIComponent(fragment.slice(1));
  } catch {
    return false;
  }
  const html = readFileSync(htmlFile, 'utf8');
  const anchors = [...html.matchAll(/\b(?:id|name)=(?:"([^"]+)"|'([^']+)')/g)]
    .map((match) => match[1] ?? match[2]);
  return anchors.includes(decodedFragment);
}

const failures = [];
const htmlFiles = filesBelow(siteDirectory).filter((path) => extname(path) === '.html');
const attributePattern = /\b(?:href|src)=(?:"([^"]+)"|'([^']+)')/g;

for (const htmlFile of htmlFiles) {
  const html = readFileSync(htmlFile, 'utf8');
  for (const match of html.matchAll(attributePattern)) {
    const rawValue = match[1] ?? match[2];
    if (rawValue.startsWith('#')) {
      if (!hasFragment(htmlFile, rawValue)) {
        failures.push(`${htmlFile}: missing fragment ${rawValue}`);
      }
      continue;
    }
    const target = localTarget(rawValue);
    if (!target) continue;
    if (target.error) {
      failures.push(`${htmlFile}: ${target.error}`);
      continue;
    }
    if (!target.candidates.some(existsSync)) {
      failures.push(`${htmlFile}: missing target ${target.rawValue}`);
      continue;
    }
    if (target.fragment) {
      const targetHTML = target.candidates.find(
        (candidate) => existsSync(candidate) && lstatSync(candidate).isFile() && extname(candidate) === '.html'
      );
      if (!targetHTML || !hasFragment(targetHTML, target.fragment)) {
        failures.push(`${htmlFile}: missing fragment ${target.rawValue}`);
      }
    }
  }
}

if (failures.length > 0) {
  throw new Error(`Broken internal links:\n${failures.join('\n')}`);
}

console.log(`Checked ${htmlFiles.length} HTML files under ${siteDirectory}`);

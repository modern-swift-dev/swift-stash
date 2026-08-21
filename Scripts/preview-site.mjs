import { createReadStream, existsSync, lstatSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, normalize, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const siteDirectory = resolve(fileURLToPath(new URL('../docs', import.meta.url)));
const siteBasePath = '/swift-stash';
const port = Number.parseInt(process.env.PORT ?? '4321', 10);
const contentTypes = new Map([
  ['.css', 'text/css; charset=utf-8'],
  ['.html', 'text/html; charset=utf-8'],
  ['.ico', 'image/x-icon'],
  ['.js', 'text/javascript; charset=utf-8'],
  ['.json', 'application/json; charset=utf-8'],
  ['.svg', 'image/svg+xml'],
  ['.woff', 'font/woff'],
  ['.woff2', 'font/woff2'],
]);

if (!existsSync(siteDirectory)) {
  throw new Error('Build the site with `make site-build` before previewing it.');
}

function requestedFile(urlValue) {
  const url = new URL(urlValue, `http://localhost:${port}`);
  if (url.pathname === '/') return { redirect: `${siteBasePath}/` };
  if (url.pathname !== siteBasePath && !url.pathname.startsWith(`${siteBasePath}/`)) return undefined;

  let relativePath;
  try {
    relativePath = decodeURIComponent(url.pathname.slice(siteBasePath.length)).replace(/^\/+/, '');
  } catch {
    return undefined;
  }

  const path = normalize(join(siteDirectory, relativePath));
  if (path !== siteDirectory && !path.startsWith(`${siteDirectory}${sep}`)) return undefined;
  if (existsSync(path) && lstatSync(path).isFile()) return path;
  if (existsSync(path) && lstatSync(path).isDirectory()) {
    const indexPath = join(path, 'index.html');
    return existsSync(indexPath) ? indexPath : undefined;
  }
  const htmlPath = `${path}.html`;
  return existsSync(htmlPath) ? htmlPath : undefined;
}

createServer((request, response) => {
  const result = requestedFile(request.url ?? '/');
  if (result?.redirect) {
    response.writeHead(302, { Location: result.redirect });
    response.end();
    return;
  }
  if (typeof result !== 'string') {
    response.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    response.end('Not found');
    return;
  }

  response.writeHead(200, {
    'Content-Type': contentTypes.get(extname(result)) ?? 'application/octet-stream',
  });
  createReadStream(result).pipe(response);
}).listen(port, '127.0.0.1', () => {
  console.log(`Previewing ${siteDirectory} at http://127.0.0.1:${port}${siteBasePath}/`);
});

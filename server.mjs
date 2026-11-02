import http from 'node:http';
import {readFile, stat} from 'node:fs/promises';
import {resolve, sep, extname} from 'node:path';
import {fileURLToPath} from 'node:url';

const project = fileURLToPath(new URL('.', import.meta.url));
const root = resolve(project, 'build/web');
const port = Number(process.env.PORT || process.argv[2] || 8090);
const types = {'.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png', '.svg': 'image/svg+xml', '.ttf': 'font/ttf', '.otf': 'font/otf'};
http.createServer(async (request, response) => {
  try {
    const path = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
    let target = resolve(root, `.${path}`);
    if (target !== root && !target.startsWith(root + sep)) { response.writeHead(403).end(); return; }
    try { if (!(await stat(target)).isFile()) target = resolve(root, 'index.html'); }
    catch { target = resolve(root, 'index.html'); }
    const data = await readFile(target);
    response.writeHead(200, {'Content-Type': types[extname(target)] || 'application/octet-stream', 'Cache-Control': 'no-cache'});
    response.end(data);
  } catch { response.writeHead(404).end('Build the application with start.ps1 first.'); }
}).listen(port, '127.0.0.1', () => console.log(`Autoritm: http://127.0.0.1:${port}`));

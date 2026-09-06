import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { esc } from './util.js';

export const MAX_BODY = 256 * 1024;

/* ------------------------------ kokosi ------------------------------ */
export function parseCookies(header = '') {
  const out = {};
  for (const part of String(header).split(';')) {
    const i = part.indexOf('=');
    if (i === -1) continue;
    const k = part.slice(0, i).trim();
    if (!k) continue;
    try {
      out[k] = decodeURIComponent(part.slice(i + 1).trim());
    } catch {
      out[k] = part.slice(i + 1).trim();
    }
  }
  return out;
}

export function cookieHeader(name, value, { maxAge, httpOnly = true, sameSite = 'Lax', secure = false, path: p = '/' } = {}) {
  const bits = [`${name}=${encodeURIComponent(value ?? '')}`, `Path=${p}`, `SameSite=${sameSite}`];
  if (httpOnly) bits.push('HttpOnly');
  if (secure) bits.push('Secure');
  if (maxAge !== undefined) bits.push(`Max-Age=${Math.floor(maxAge)}`);
  return bits.join('; ');
}

/* ------------------------------ telo ------------------------------ */
export async function readBody(req, limit = MAX_BODY) {
  return await new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (c) => {
      size += c.length;
      if (size > limit) {
        reject(Object.assign(new Error('telo zahteve je preveliko'), { status: 413 }));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

/** Podpira application/x-www-form-urlencoded in application/json. */
export async function parseBody(req, contentType = '') {
  const type = String(contentType).split(';')[0].trim().toLowerCase();
  if (req.method === 'GET' || req.method === 'HEAD') return {};
  const buf = await readBody(req);
  if (!buf.length) return {};
  if (type === 'application/json') {
    try {
      const obj = JSON.parse(buf.toString('utf8'));
      return obj && typeof obj === 'object' ? obj : {};
    } catch {
      throw Object.assign(new Error('neveljaven JSON'), { status: 400 });
    }
  }
  const params = new URLSearchParams(buf.toString('utf8'));
  const out = {};
  for (const [k, v] of params) out[k] = v;
  return out;
}

/* ------------------------------ odgovori ------------------------------ */
export function send(res, status, body, headers = {}) {
  if (res.writableEnded) return;
  const h = { 'X-Content-Type-Options': 'nosniff', ...headers };
  res.writeHead(status, h);
  res.end(body);
}

export function sendHtml(res, htmlStr, status = 200, headers = {}) {
  send(res, status, htmlStr, { 'Content-Type': 'text/html; charset=utf-8', ...headers });
}

export function sendJson(res, obj, status = 200, headers = {}) {
  send(res, status, JSON.stringify(obj, null, 2), { 'Content-Type': 'application/json; charset=utf-8', ...headers });
}

export function redirect(res, location, status = 302, headers = {}) {
  send(res, status, `Preusmerjam na <a href="${esc(location)}">${esc(location)}</a>`, {
    Location: location, 'Content-Type': 'text/html; charset=utf-8', ...headers,
  });
}

export function securityHeaders({ csp }) {
  return {
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY',
    'Referrer-Policy': 'same-origin',
    'Permissions-Policy': 'geolocation=(), microphone=(), camera=()',
    'Content-Security-Policy': csp,
    'Cache-Control': 'no-store',
  };
}

/* ------------------------------ statične datoteke ------------------------------ */
const MIME = {
  '.css': 'text/css; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.ico': 'image/x-icon',
  '.txt': 'text/plain; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.woff2': 'font/woff2',
};

/** Postrežitev datoteke iz root-a (brez prečkanja poteh). vrne true, če je postreženo. */
export function serveStatic(rootDir, urlPath, req, res, { immutable = false } = {}) {
  const clean = decodeURIComponent(urlPath.split('?')[0]).replace(/[\\]/g, '/');
  if (clean.includes('..') || clean.includes('\0')) return false;
  const rel = clean.replace(/^\/+/, '');
  const abs = path.resolve(rootDir, rel);
  if (abs !== rootDir && !abs.startsWith(rootDir + path.sep)) return false;
  let stat;
  try {
    stat = fs.statSync(abs);
  } catch {
    return false;
  }
  if (stat.isDirectory()) return false;
  const ext = path.extname(abs).toLowerCase();
  const etag = `W/"${stat.size.toString(16)}-${createHash('sha1').update(`${abs}:${stat.mtimeMs}`).digest('hex').slice(0, 16)}"`;
  if (req.headers['if-none-match'] === etag) {
    send(res, 304, '', { ETag: etag });
    return true;
  }
  res.writeHead(200, {
    'Content-Type': MIME[ext] || 'application/octet-stream',
    'Content-Length': stat.size,
    ETag: etag,
    'Cache-Control': immutable ? 'public, max-age=31536000, immutable' : 'public, max-age=300',
    'X-Content-Type-Options': 'nosniff',
  });
  fs.createReadStream(abs).pipe(res);
  return true;
}

export function clientIp(req, trustProxy = true) {
  if (trustProxy) {
    const xff = req.headers['x-forwarded-for'];
    if (xff) return String(xff).split(',')[0].trim();
    const real = req.headers['x-real-ip'];
    if (real) return String(real).trim();
  }
  return req.socket?.remoteAddress || '-';
}

export function isHttps(req, config) {
  const mode = String(config.secureCookies ?? 'auto').toLowerCase();
  if (mode === 'true' || mode === 'always') return true;
  if (mode === 'false' || mode === 'never') return false;
  const proto = req.headers['x-forwarded-proto'] || (config.publicUrl.startsWith('https') ? 'https' : 'http');
  return String(proto).split(',')[0].trim() === 'https';
}

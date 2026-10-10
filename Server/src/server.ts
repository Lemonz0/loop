import * as http from 'node:http';
import * as path from 'node:path';
import { pathToFileURL } from 'node:url';
import { WebSocketServer } from 'ws';
import { WebSocketHub } from './wsHub.js';
import { saveUploadedFile, streamMediaFile } from './storage.js';
import { SocialStore } from './social.js';
import { uploadSocialPhoto } from './socialMedia.js';
import { AuthStore, ApiError } from './auth.js';
import { serverLogger } from './logger.js';

function json(res: http.ServerResponse, status: number, body: unknown) {
  res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(body));
}
function bearer(req: http.IncomingMessage): string {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) throw new ApiError(401, 'Authentication required');
  return header.slice(7);
}
function readJSON(req: http.IncomingMessage): Promise<Record<string, unknown>> {
  return new Promise((resolve, reject) => {
    let bytes = 0, settled = false; const chunks: Buffer[] = [];
    req.on('data', (chunk: Buffer) => {
      if (settled) return;
      bytes += chunk.length;
      if (bytes > 16384) { settled = true; reject(new ApiError(413, 'Request is too large')); return; }
      chunks.push(chunk);
    });
    req.on('end', () => {
      if (settled) return;
      try {
        const data = JSON.parse(Buffer.concat(chunks).toString('utf8'));
        if (!data || typeof data !== 'object' || Array.isArray(data)) throw new Error();
        resolve(data);
      } catch { reject(new ApiError(400, 'Invalid JSON body')); }
    });
    req.on('error', reject);
  });
}
export function createLoopServer(options: { dataDirectory?: string; bootstrapKey?: string; now?: () => number } = {}) {
  const auth = new AuthStore(options.dataDirectory ?? path.resolve(process.cwd(), 'data'), options.bootstrapKey ?? process.env.INVITE_KEY, options.now);
  const uploadsDirectory = options.dataDirectory ? path.join(options.dataDirectory, 'uploads') : undefined;
  const social = new SocialStore(auth, options.dataDirectory ?? path.resolve(process.cwd(), 'data'), uploadsDirectory ?? path.resolve(process.cwd(), 'uploads'), options.now);
  const attempts = new Map<string, { count: number; expiresAt: number }>();
  const server = http.createServer((req, res) => {
    void (async () => {
      const url = new URL(req.url ?? '/', 'http://localhost');
      if (url.pathname === '/health' && req.method === 'GET') { json(res, 200, { status: 'ok', service: 'Loop Hub' }); return; }
      if (req.method === 'POST' && ['/api/auth/invite', '/api/auth/login'].includes(url.pathname)) {
        const now = Date.now(), ip = req.socket.remoteAddress ?? 'unknown';
        for (const [key, value] of attempts) if (value.expiresAt <= now) attempts.delete(key);
        if (!attempts.has(ip) && attempts.size >= 10000) throw new ApiError(429, 'Try again later');
        const attempt = attempts.get(ip) ?? { count: 0, expiresAt: now + 60000 }; attempts.set(ip, attempt);
        if (++attempt.count > 10) { res.setHeader('Retry-After', '60'); throw new ApiError(429, 'Try again later'); }
        const body = await readJSON(req);
        const session = url.pathname.endsWith('/invite') ? await auth.redeemInvite(body) : await auth.login(body);
        if (url.pathname.endsWith('/invite')) hub.notifyAccountChange(session.user.id);
        json(res, 200, { success: true, session }); return;
      }
      const token = bearer(req), user = auth.authenticate(token);
      if (url.pathname === '/api/calls/ice' && req.method === 'GET') {
        const servers: { urls: string[]; username?: string; credential?: string }[] = [{ urls: ['stun:stun.l.google.com:19302'] }];
        if (process.env.TURN_URL && process.env.TURN_USERNAME && process.env.TURN_PASSWORD) servers.push({ urls: process.env.TURN_URL.split(','), username: process.env.TURN_USERNAME, credential: process.env.TURN_PASSWORD });
        json(res, 200, { servers }); return;
      }
      const memberRoute = /^\/api\/circles\/([^/]+)\/members$/.exec(url.pathname);
      if (memberRoute && req.method === 'GET') { json(res, 200, { users: auth.members(user.id, memberRoute[1]) }); return; }
      if (url.pathname === '/api/auth/me'  && req.method === 'GET') { json(res, 200, { user, circles: auth.circlesFor(user.id) }); return; }
      if (url.pathname === '/api/auth/profile' && req.method === 'POST') { const profile = auth.updateProfile(user.id, await readJSON(req)); hub.notifyAccountChange(user.id); json(res, 200, { user: profile }); return; }
      const renameRoute = /^\/api\/circles\/([^/]+)\/rename$/.exec(url.pathname);
      if (renameRoute && req.method === 'POST') { const body = await readJSON(req); const circle = auth.renameCircle(user.id, renameRoute[1], body.name); hub.notifyCircleChange(circle.roomId); json(res, 200, { circle }); return; }
      if (url.pathname === '/api/auth/logout' && req.method === 'POST') { auth.logout(token); json(res, 200, { success: true }); return; }
      if (url.pathname === '/api/chats' && req.method === 'GET') { json(res, 200, { rooms: auth.chatRooms(user.id) }); return; }
      if (url.pathname === '/api/chats/direct' && req.method === 'POST') { const body = await readJSON(req); const room = auth.directRoom(user.id, body.userId); hub.synchronizeRooms(); json(res, 200, { room }); return; }
      if (url.pathname === '/api/circles' && req.method === 'GET') { json(res, 200, { circles: auth.circlesFor(user.id) }); return; }
      if (url.pathname === '/api/circles' && req.method === 'POST') { const body = await readJSON(req); const circle = auth.createCircle(user.id, body.name); hub.synchronizeRooms(); json(res, 201, { circle }); return; }
      if (url.pathname === '/api/invites/join' && req.method === 'POST') { const body = await readJSON(req); const circle = auth.joinInvite(user.id, body.secretKey); hub.notifyAccountChange(user.id); json(res, 200, { circle }); return; }
      if (url.pathname === '/api/social/consent' && req.method === 'POST') {
        const body = await readJSON(req); if (typeof body.allowed !== 'boolean') throw new ApiError(400, 'Invalid consent');
        auth.setConsent(user.id, body.allowed); json(res, 200, { success: true }); return;
      }
      const socialRoute = /^\/api\/circles\/([^/]+)\/social(?:\/(posts|stories|trolls|media|reports|replies))?(?:\/([^/]+))?(?:\/([a-z]+))?$/.exec(url.pathname);
      if (socialRoute) {
        const [, circleId, kind, id, action] = socialRoute;
        auth.members(user.id, circleId);
        if (!kind && req.method === 'GET') { json(res, 200, social.snapshot(user.id, circleId)); return; }
        if (kind === 'media' && req.method === 'POST') { json(res, 201, await uploadSocialPhoto(req, auth, user.id, circleId, uploadsDirectory ?? path.resolve(process.cwd(), 'uploads'))); return; }
        if (kind === 'posts' && id && action === 'likes' && req.method === 'GET') { json(res, 200, social.postLikes(user.id, circleId, id)); return; }
        if (kind === 'replies' && req.method === 'GET') { json(res, 200, { replies: social.inbox(user.id, circleId) }); return; }
        if (kind === 'reports' && req.method === 'GET') { json(res, 200, { reports: social.reports(user.id, circleId) }); return; }
        if (kind === 'stories' && id && action === 'replies' && req.method === 'GET') { json(res, 200, { replies: social.replies(user.id, circleId, id) }); return; }
        if (kind === 'trolls' && id && action === 'remove' && req.method === 'POST') { json(res, 200, social.removeTroll(user.id, circleId, id)); return; }
        if (['posts','stories','trolls'].includes(kind) && req.method === 'POST') {
          const body = await readJSON(req);
          if (!id) { json(res, 201, social.create(user.id, circleId, kind, body)); return; }
          if (action) { json(res, 200, social.action(user.id, circleId, kind, id, action, body)); return; }
        }
        throw new ApiError(404, 'Social endpoint not found');
      }
      const inviteRoute = /^\/api\/circles\/([^/]+)\/invites$/.exec(url.pathname);
      if (inviteRoute && req.method === 'POST') { json(res, 201, auth.createInvite(user.id, inviteRoute[1])); return; }
      if (url.pathname === '/api/media/upload' && req.method === 'POST') {
        const roomId = req.headers['x-room-id'];
        if (typeof roomId === 'string' && auth.isDirectRoom(roomId)) {
          if (!auth.canAccessRoom(user.id, roomId)) throw new ApiError(403, 'Direct room membership required');
          const name = typeof req.headers['x-file-name'] === 'string' ? req.headers['x-file-name'] : 'upload.bin';
          const saved = await saveUploadedFile(req, name, uploadsDirectory); auth.registerRoomMedia(user.id, roomId, path.basename(saved.savedPath));
          json(res, 200, { fileUrl: saved.publicUrl, byteSize: saved.byteSize }); return;
        }
        if (roomId !== undefined && (typeof roomId !== 'string' || !auth.canAccessRoom(user.id, roomId))) throw new ApiError(403, 'Room membership required');
        const circles = auth.circlesFor(user.id);
        const circleId = req.headers['x-circle-id'] ?? circles[0]?.id;
        if (typeof circleId !== 'string' || !circles.some(c => c.id === circleId)) throw new ApiError(403, 'Circle membership required');
        const fileName = typeof req.headers['x-file-name'] === 'string' ? req.headers['x-file-name'] : 'upload.bin';
        const saved = await saveUploadedFile(req, fileName, uploadsDirectory);
        auth.registerMedia(user.id, circleId, path.basename(saved.savedPath));
        // Relative URL avoids trusting forwarded Host/Proto supplied by arbitrary clients.
        json(res, 200, { fileUrl: saved.publicUrl, byteSize: saved.byteSize }); return;
      }
      if (url.pathname.startsWith('/uploads/') && req.method === 'GET') {
        const filename = url.pathname.slice('/uploads/'.length);
        if (filename !== path.basename(filename) || (!auth.canAccessMedia(user.id, filename) || !social.canReadMedia(user.id, filename))) throw new ApiError(404, 'File not found');
        res.setHeader('Cache-Control', 'private, no-store'); streamMediaFile(req, res, filename, uploadsDirectory); return;
      }
      json(res, 404, { error: 'Endpoint not found' });
    })().catch(error => {
      const status = error instanceof ApiError ? error.status : 500;
      if (status === 500) serverLogger.error('HTTP_ERROR', 'Request failed');
      if (!res.headersSent) json(res, status, { success: false, errorMessage: status === 500 ? 'Internal server error' : error.message });
      else res.destroy();
    });
  });
  const wss = new WebSocketServer({ noServer: true, maxPayload: 256 * 1024 });
  const hub = new WebSocketHub(wss, auth, options.dataDirectory);
  server.on('upgrade', (request, socket, head) => {
    if (wss.clients.size >= 1000) { socket.destroy(); return; }
    if (new URL(request.url ?? '/', 'http://localhost').pathname !== '/ws') { socket.destroy(); return; }
    wss.handleUpgrade(request, socket, head, ws => { wss.emit('connection', ws, request); });
  });
  return { server, wss, auth, social };
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const { server } = createLoopServer();
  const port = Number(process.env.PORT ?? 8080);
  server.listen(port, process.env.HOST ?? '127.0.0.1', () => serverLogger.info('SERVER_START', `Loop Hub listening on port ${port}`));
}

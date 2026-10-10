import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { once } from 'node:events';
import { WebSocket } from 'ws';
import { AuthStore } from '../dist/auth.js';
import { createLoopServer } from '../dist/server.js';
const bootstrap = 'test-only-bootstrap-invite-with-32-bytes';
const input = (secretKey, username) => ({ secretKey, username, chosenDisplayName: username, password: 'test-password-12345' });
function directory(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'loop-auth-tests-'));
  t.after(() => { assert.equal(path.dirname(root), os.tmpdir()); assert.ok(path.basename(root).startsWith('loop-auth-tests-')); fs.rmSync(root, { recursive: true, force: true }); });
  return root;
}
test('invite is exact, single-use; persisted storage contains no raw secrets', async t => {
  const root = directory(t), store = new AuthStore(root, bootstrap);
  await assert.rejects(store.redeemInvite(input('arbitrary-eight-characters', 'stranger')), /Invalid or expired invite/);
  const session = await store.redeemInvite(input(bootstrap, 'owner'));
  await assert.rejects(store.redeemInvite(input(bootstrap, 'intruder')), /Invalid or expired invite/);
  const saved = fs.readFileSync(path.join(root, 'auth.json'), 'utf8');
  for (const secret of [bootstrap, session.token, 'test-password-12345']) assert.ok(!saved.includes(secret));
  const restarted = new AuthStore(root);
  assert.equal(restarted.authenticate(session.token).id, session.user.id);
  const loggedIn = await restarted.login({ username: 'OWNER', password: 'test-password-12345' });
  assert.equal(loggedIn.user.id, session.user.id);
  await assert.rejects(restarted.login({ username: 'owner', password: 'incorrect' }), /Invalid username or password/);
});
test('owner-only invitations, cross-circle membership, and revocation', async t => {
  const store = new AuthStore(directory(t), bootstrap);
  const owner = await store.redeemInvite(input(bootstrap, 'owner'));
  const invitation = store.createInvite(owner.user.id, 'circle_main');
  const friend = await store.redeemInvite(input(invitation.code, 'friend'));
  assert.throws(() => store.createInvite(friend.user.id, 'circle_main'), /Only the circle owner/);
  const separate = store.createCircle(owner.user.id, 'Private');
  assert.equal(store.canAccessRoom(friend.user.id, separate.roomId), false);
  store.joinInvite(friend.user.id, store.createInvite(owner.user.id, separate.id).code);
  assert.equal(store.canAccessRoom(friend.user.id, separate.roomId), true);
  store.logout(friend.token);
  assert.throws(() => store.authenticate(friend.token), /Invalid or expired session/);
});
test('simultaneous invite redemption has one winner and expiration is enforced', async t => {
  let now = Date.now(); const store = new AuthStore(directory(t), bootstrap, () => now);
  const results = await Promise.allSettled([store.redeemInvite(input(bootstrap, 'alice')), store.redeemInvite(input(bootstrap, 'bob'))]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  const session = results.find(r => r.status === 'fulfilled').value;
  const invite = store.createInvite(session.user.id, 'circle_main');
  now += 8 * 86400000;
  await assert.rejects(store.redeemInvite(input(invite.code, 'late')), /Invalid or expired invite/);
  now += 23 * 86400000;
  assert.throws(() => store.authenticate(session.token), /Invalid or expired session/);
});
test('missing bootstrap configuration fails closed', t => {
  assert.throws(() => new AuthStore(directory(t)), /Set INVITE_KEY/);
});
async function running(t) {
  const app = createLoopServer({ dataDirectory: directory(t), bootstrapKey: bootstrap });
  app.server.listen(0, '127.0.0.1'); await once(app.server, 'listening');
  const base = `http://127.0.0.1:${app.server.address().port}`;
  t.after(async () => { for (const ws of app.wss.clients) ws.terminate(); app.wss.close(); app.server.closeAllConnections(); await new Promise(resolve => app.server.close(resolve)); });
  return { ...app, base };
}
async function request(base, route, body, token) {
  const response = await fetch(base + route, { method: body === undefined ? 'GET' : 'POST', headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, body: body === undefined ? undefined : JSON.stringify(body) });
  return { status: response.status, body: await response.json() };
}
function message(ws, predicate) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => { ws.off('message', receive); reject(new Error('WebSocket response timeout')); }, 3000);
    function receive(raw) { const data = JSON.parse(raw); if (predicate(data)) { clearTimeout(timer); ws.off('message', receive); resolve(data); } }
    ws.on('message', receive);
  });
}
test('HTTP auth contract protects sessions, circles, and media', async t => {
  const app = await running(t);
  assert.equal((await request(app.base, '/health')).status, 200);
  assert.equal((await request(app.base, '/api/circles')).status, 401);
  assert.equal((await request(app.base, '/api/media/upload', {})).status, 401);
  assert.equal((await request(app.base, '/uploads/unknown.jpg')).status, 401);
  const registration = await request(app.base, '/api/auth/invite', input(bootstrap, 'owner'));
  assert.equal(registration.status, 200); const session = registration.body.session;
  const profile = await request(app.base, '/api/auth/me', undefined, session.token);
  assert.equal(profile.body.user.id, session.user.id);
  assert.ok(profile.body.circles[0].roomId);
  assert.notEqual(profile.body.circles[0].roomId, 'room_main');
  assert.equal((await request(app.base, '/api/auth/logout', {}, session.token)).status, 200);
  assert.equal((await request(app.base, '/api/auth/me', undefined, session.token)).status, 401);
});
test('WebSockets reject fabricated sessions, room access, and sender spoofing', async t => {
  const app = await running(t), session = await app.auth.redeemInvite(input(bootstrap, 'owner'));
  const roomId = app.auth.roomsFor(session.user.id)[0];
  const fake = new WebSocket(app.base.replace('http:', 'ws:') + '/ws'); await once(fake, 'open');
  const rejected = message(fake, m => m.type === 'error');
  fake.send(JSON.stringify({ type: 'auth', token: 'local_session_token', user: { id: 'owner' } }));
  assert.match((await rejected).reason, /Invalid or expired/); fake.terminate();
  const ws = new WebSocket(app.base.replace('http:', 'ws:') + '/ws'); await once(ws, 'open'); t.after(() => ws.terminate());
  const authenticated = message(ws, m => m.type === 'authenticated');
  ws.send(JSON.stringify({ type: 'auth', token: session.token, user: { id: 'spoofed', displayName: 'Fake' } }));
  assert.equal((await authenticated).user.id, session.user.id);
  const denied = message(ws, m => m.type === 'error');
  ws.send(JSON.stringify({ type: 'join_room', roomId: 'room_elena' }));
  assert.match((await denied).reason, /membership/);
  const received = message(ws, m => m.type === 'message_received');
  ws.send(JSON.stringify({ type: 'send_message', roomId, message: { id: 'test-message', content: 'Hello', senderId: 'spoofed', senderName: 'Fake', roomId: 'other-room' } }));
  const result = (await received).message;
  assert.equal(result.senderId, session.user.id); assert.equal(result.senderName, 'owner'); assert.equal(result.roomId, roomId);
  app.auth.logout(session.token);
  const expired = message(ws, m => m.type === 'error'); ws.send(JSON.stringify({ type: 'ping' }));
  assert.match((await expired).reason, /Authentication/);
});

test('media ownership prevents cross-circle reads and bad ranges return 416', async t => {
  const app = await running(t), owner = await app.auth.redeemInvite(input(bootstrap, 'owner'));
  const stranger = await app.auth.redeemInvite(input(app.auth.createInvite(owner.user.id, 'circle_main').code, 'stranger'));
  const privateCircle = app.auth.createCircle(owner.user.id, 'Owner only');
  const upload = await fetch(app.base + '/api/media/upload', { method: 'POST', headers: { Authorization: 'Bearer ' + owner.token, 'X-Circle-ID': privateCircle.id, 'X-File-Name': 'photo.png' }, body: Buffer.from([1,2,3,4]) });
  assert.equal(upload.status, 200); const { fileUrl } = await upload.json();
  assert.equal((await fetch(app.base + fileUrl, { headers: { Authorization: 'Bearer ' + stranger.token } })).status, 404);
  const read = await fetch(app.base + fileUrl, { headers: { Authorization: 'Bearer ' + owner.token, Range: 'bytes=1-2' } });
  assert.equal(read.status, 206); assert.deepEqual([...new Uint8Array(await read.arrayBuffer())], [2,3]);
  assert.equal((await fetch(app.base + fileUrl, { headers: { Authorization: 'Bearer ' + owner.token, Range: 'bytes=999-1' } })).status, 416);
});

test('authentication attempts are rate-limited and oversized JSON is rejected', async t => {
  const app = await running(t);
  const oversized = await request(app.base, '/api/auth/login', { username: 'owner', password: 'x'.repeat(17000) });
  assert.equal(oversized.status, 413);
  for (let i=0;i<9;i++) await request(app.base, '/api/auth/login', {});
  assert.equal((await request(app.base, '/api/auth/login', {})).status, 429);
});

test('profile edits persist and stay attached to the signed-in account', async t => {
  const app = await running(t), session = await app.auth.redeemInvite(input(bootstrap, 'owner'));
  const updated = await request(app.base, '/api/auth/profile', { displayName: 'Maya' }, session.token);
  assert.equal(updated.status, 200); assert.equal(updated.body.user.id, session.user.id);
  assert.equal((await request(app.base, '/api/auth/me', undefined, session.token)).body.user.displayName, 'Maya');
  assert.equal((await request(app.base, '/api/auth/profile', { displayName: 'Other' })).status, 401);
});

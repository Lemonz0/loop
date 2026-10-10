import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { CallICEProvider } from '../dist/callIce.js';
import { PushStore } from '../dist/push.js';
import { AuthStore } from '../dist/auth.js';

test('ICE keeps direct candidates and caches expiring Cloudflare credentials without exposing the key', async () => {
  let now = 1000, requests = 0;
  const provider = new CallICEProvider({ cloudflareKeyId: 'test-key', cloudflareToken: 'long-lived-secret', now: () => now,
    fetch: async (url, request) => {
      requests++; assert.ok(url.endsWith('/credentials/generate-ice-servers'));
      assert.equal(request.headers.Authorization, 'Bearer long-lived-secret'); assert.equal(JSON.parse(request.body).ttl, 86400);
      return Response.json({ iceServers: [{ urls: ['stun:stun.cloudflare.com:3478'] }, { urls: ['turn:turn.cloudflare.com:3478?transport=udp', 'turns:turn.cloudflare.com:443?transport=tcp'], username: 'temporary-user', credential: 'temporary-password' }] });
    } });
  const [first, second] = await Promise.all([provider.servers(), provider.servers()]);
  assert.equal(requests, 1); assert.deepEqual(first, second);
  assert.ok(first[0].urls.every(url => url.startsWith('stun:')));
  assert.equal(first[1].credential, 'temporary-password'); assert.ok(!JSON.stringify(first).includes('long-lived-secret'));
  await provider.servers(); assert.equal(requests, 1);
  now += 24 * 3600000; await provider.servers(); assert.equal(requests, 2);
});

test('ICE handles missing TURN and never includes provider errors or credentials in failures', async () => {
  assert.equal((await new CallICEProvider({}).servers()).length, 1);
  const broken = new CallICEProvider({ cloudflareKeyId: 'id', cloudflareToken: 'secret', fetch: async () => { throw Error('secret'); } });
  await assert.rejects(broken.servers(), error => error.status === 503 && !error.message.includes('secret'));
  const malformed = new CallICEProvider({ cloudflareKeyId: 'id', cloudflareToken: 'secret', fetch: async () => Response.json({ iceServers: [{}] }) });
  await assert.rejects(malformed.servers(), /relay is temporarily unavailable/);
});

test('push is private, session-bound, revocation-safe and removes invalid devices', async t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'loop-push-tests-'));
  t.after(() => { assert.equal(path.dirname(directory), os.tmpdir()); assert.ok(path.basename(directory).startsWith('loop-push-tests-')); fs.rmSync(directory, { recursive: true, force: true }); });
  const bootstrap = 'test-only-bootstrap-invite-with-32-bytes';
  const auth = new AuthStore(directory, bootstrap);
  const session = await auth.redeemInvite({ secretKey: bootstrap, username: 'owner', chosenDisplayName: 'Owner', password: 'test-password-12345' });
  const room = auth.chatRooms(session.user.id)[0];
  const sent = []; let status = 200;
  const options = { topic: 'com.example.loop', send: async (device, payload) => { sent.push({ device, payload }); return status; } };
  const push = new PushStore(auth, directory, options);
  const body = { deviceToken: 'ab'.repeat(32), topic: options.topic, environment: 'development', sound: false };
  assert.throws(() => push.register(session.user.id, session.token, { ...body, topic: 'attacker.bundle' }), /Invalid push/);
  push.register(session.user.id, session.token, body);
  assert.ok(!fs.readFileSync(path.join(directory, 'push-devices.json'), 'utf8').includes(session.token));
  const message = { id: 'message1', roomId: room.id, senderId: 'other-user', senderName: 'Private sender', content: 'PRIVATE MESSAGE CONTENT', timestamp: new Date().toISOString(), status: 'sent' };
  await push.message([session.user.id], message);
  assert.equal(sent.length, 1); assert.equal(sent[0].payload.aps.sound, undefined);
  assert.ok(!JSON.stringify(sent[0].payload).includes(message.content)); assert.ok(!JSON.stringify(sent[0].payload).includes(message.senderName));
  assert.equal(sent[0].payload.userId, session.user.id);
  await push.message([], message); assert.equal(sent.length, 1);
  await push.message([session.user.id], { ...message, roomId: 'unrelated-room' }); assert.equal(sent.length, 1);
  push.register(session.user.id, session.token, body); status = 410;
  await push.message([session.user.id], message); assert.equal(sent.length, 2);
  await push.message([session.user.id], message); assert.equal(sent.length, 2);
  push.register(session.user.id, session.token, body); auth.logout(session.token);
  await new PushStore(auth, directory, options).message([session.user.id], message); assert.equal(sent.length, 2);
  assert.deepEqual(new PushStore(auth, directory, {}).register(session.user.id, 'invalid', {}), { available: false, registered: false });
});

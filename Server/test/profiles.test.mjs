import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { once } from 'node:events';
import { WebSocket } from 'ws';
import { createLoopServer } from '../dist/server.js';
import { ProfileStore } from '../dist/profiles.js';

const bootstrap = 'profile-tests-bootstrap-only-secret';
async function fixture(t) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'loop-profile-tests-'));
  const app = createLoopServer({ dataDirectory: directory, bootstrapKey: bootstrap });
  app.server.listen(0, '127.0.0.1'); await once(app.server, 'listening');
  const base = `http://127.0.0.1:${app.server.address().port}`;
  t.after(async () => {
    for (const socket of app.wss.clients) socket.terminate(); app.wss.close(); app.server.closeAllConnections();
    await new Promise(resolve => app.server.close(resolve));
    assert.equal(path.dirname(directory), os.tmpdir()); assert.ok(path.basename(directory).startsWith('loop-profile-tests-'));
    fs.rmSync(directory, { recursive: true, force: true });
  });
  const redeem = (code, username) => app.auth.redeemInvite({ secretKey: code, username, chosenDisplayName: username, password: 'profile-test-password-1234' });
  const owner = await redeem(bootstrap, 'owner');
  const friend = await redeem(app.auth.createInvite(owner.user.id, 'circle_main').code, 'friend');
  const third = await redeem(app.auth.createInvite(owner.user.id, 'circle_main').code, 'third');
  const request = async (route, session = owner, body) => {
    const response = await fetch(base + route, { method: body === undefined ? 'GET' : 'POST', headers: { Authorization: 'Bearer ' + session.token, 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) });
    return { status: response.status, data: await response.json() };
  };
  return { ...app, directory, base, owner, friend, third, request };
}
const details = overrides => ({ bio: 'Private bio', pronouns: 'they/them', status: 'Focused', timeZone: 'Europe/Bucharest', showLocalTime: true, private: false, presence: 'everyone', links: ['https://example.com'], ...overrides });
test('profile API enforces privacy, contacts, blocking, safe links, and viewer-only notes across restart', async t => {
  const f = await fixture(t), id = f.friend.user.id;
  assert.equal((await f.request('/api/profiles/settings', f.friend, details({}))).status, 200);
  await f.request(`/api/profiles/${id}/actions`, f.owner, { action: 'note', nickname: 'Best friend', note: 'Only me' });
  let card = (await f.request(`/api/profiles/${id}`, f.owner)).data;
  assert.equal(card.bio, 'Private bio'); assert.equal(card.personal.note, 'Only me'); assert.ok(card.memberSince);
  assert.equal((await f.request(`/api/profiles/${id}`, f.third)).data.personal.note, '');
  const restarted = new ProfileStore(f.auth, f.directory); assert.equal(restarted.card(f.owner.user.id, id).personal.note, 'Only me');
  await f.request('/api/profiles/settings', f.friend, details({ private: true, presence: 'nobody' }));
  card = (await f.request(`/api/profiles/${id}`, f.owner)).data;
  assert.equal(card.state, 'private'); assert.equal(card.user.username, ''); assert.equal(card.bio, undefined); assert.equal(card.timeZone, undefined); assert.equal(card.presence, undefined); assert.deepEqual(card.links, []);
  assert.equal((await f.request('/api/chats/direct', f.owner, { userId: id })).status, 403);
  await f.request(`/api/profiles/${id}/actions`, f.owner, { action: 'request' });
  assert.equal((await f.request('/api/profiles/requests', f.friend)).data.users[0].id, f.owner.user.id);
  await f.request(`/api/profiles/${f.owner.user.id}/actions`, f.friend, { action: 'contact', value: true });
  assert.equal((await f.request(`/api/profiles/${id}`, f.owner)).data.state, 'active');
  assert.equal((await f.request('/api/chats/direct', f.owner, { userId: id })).status, 200);
  await f.request(`/api/profiles/${id}/actions`, f.owner, { action: 'block', value: true });
  card = (await f.request(`/api/profiles/${id}`, f.owner)).data;
  assert.equal(card.state, 'blocked'); assert.equal(card.bio, undefined); assert.equal(card.presence, undefined); assert.equal(card.canCall, false);
  assert.equal((await f.request('/api/chats/direct', f.friend, { userId: f.owner.user.id })).status, 403);
  await f.request(`/api/profiles/${id}/actions`, f.owner, { action: 'block', value: false });
  assert.equal((await f.request(`/api/profiles/${id}`, f.owner)).data.state, 'active');
  assert.equal((await f.request('/api/profiles/settings', f.friend, details({ links: ['javascript:alert(1)'] }))).status, 400);
  assert.equal((await f.request(`/api/profiles/${id}/actions`, f.owner, { action: 'note', note: 42, nickname: '' })).status, 400);
  const unrelatedCircle = f.auth.createCircle(f.third.user.id, 'Other');
  assert.equal((await f.request(`/api/profiles/${id}?circleId=${unrelatedCircle.id}`, f.owner)).status, 404);
});
async function connect(t, base, session) {
  const ws = new WebSocket(base.replace('http:', 'ws:') + '/ws'); const events = [];
  ws.on('message', raw => events.push(JSON.parse(raw.toString())));
  await once(ws, 'open'); ws.send(JSON.stringify({ type: 'auth', token: session.token }));
  t.after(() => ws.terminate());
  async function wait(predicate) {
    for (let attempt = 0; attempt < 100; attempt++) { const index = events.findIndex(predicate); if (index >= 0) return events.splice(index, 1)[0]; await new Promise(resolve => setTimeout(resolve, 10)); }
    throw new Error('Timed out waiting for WebSocket event');
  }
  await wait(e => e.type === 'authenticated');
  return { ws, wait, events };
}
test('group actions are owner-only and restrictions/removal immediately revoke existing sockets', async t => {
  const f = await fixture(t), id = f.friend.user.id, room = f.auth.circlesFor(id)[0].roomId;
  const socket = await connect(t, f.base, f.friend);
  const route = `/api/profiles/${id}/group`;
  assert.equal((await f.request(route, f.third, { circleId: 'circle_main', action: 'remove' })).status, 403);
  assert.equal((await f.request(route, f.owner, { circleId: 'circle_main', action: 'promote' })).status, 200);
  assert.equal((await f.request(`/api/profiles/${id}?circleId=circle_main`, f.owner)).data.group.role, 'Admin');
  await f.request(route, f.owner, { circleId: 'circle_main', action: 'restrict' });
  socket.ws.send(JSON.stringify({ type: 'send_message', roomId: room, message: { id: 'restricted', content: 'Denied' } }));
  assert.match((await socket.wait(e => e.type === 'error')).reason, /restricted/);
  assert.equal((await f.request('/api/circles/circle_main/social/posts', f.friend, { caption: 'Denied' })).status, 403);
  await f.request(route, f.owner, { circleId: 'circle_main', action: 'remove' });
  assert.equal(f.auth.canAccessRoom(id, room), false);
  socket.ws.send(JSON.stringify({ type: 'join_room', roomId: room }));
  assert.match((await socket.wait(e => e.type === 'error')).reason, /membership/);
});
test('replies and reactions resolve server identities; private clear and call history cannot leak to a third user', async t => {
  const f = await fixture(t), id = f.friend.user.id;
  const room = (await f.request('/api/chats/direct', f.owner, { userId: id })).data.room;
  const owner = await connect(t, f.base, f.owner), friend = await connect(t, f.base, f.friend);
  owner.ws.send(JSON.stringify({ type: 'send_message', roomId: room.id, message: { id: 'original', content: 'https://example.com', senderId: f.third.user.id } }));
  const original = (await friend.wait(e => e.type === 'message_received')).message;
  assert.equal(original.senderId, f.owner.user.id);
  friend.ws.send(JSON.stringify({ type: 'send_message', roomId: room.id, message: { id: 'reply', content: 'Hello', replyToId: 'original' } }));
  assert.equal((await owner.wait(e => e.type === 'message_received' && e.message.id === 'reply')).message.replyToId, 'original');
  assert.equal((await f.request(`/api/chats/${room.id}/messages/original/reaction`, f.third, { emoji: '👍' })).status, 403);
  await f.request(`/api/chats/${room.id}/messages/original/reaction`, f.friend, { emoji: '👍' });
  const reacted = await owner.wait(e => e.type === 'message_received' && e.message.reactions?.length);
  assert.equal(reacted.message.reactions[0].userId, id);
  assert.equal((await f.request(`/api/profiles/${id}?roomId=${room.id}`, f.owner)).data.sharedItems.length, 1);
  await f.request(`/api/profiles/${id}/actions`, f.owner, { action: 'clear' });
  assert.equal((await f.request(`/api/profiles/${id}?roomId=${room.id}`, f.owner)).data.sharedItems.length, 0);
  assert.equal((await f.request(`/api/profiles/${f.owner.user.id}?roomId=${room.id}`, f.friend)).data.sharedItems.length, 1);
  owner.ws.send(JSON.stringify({ type: 'call_signal', roomId: room.id, callSignal: { callId: 'call-one', signalType: 'offer', isVideo: false } }));
  await friend.wait(e => e.type === 'call_signal');
  assert.equal((await f.request('/api/calls/history', f.owner)).data.calls.length, 1);
  assert.equal((await f.request('/api/calls/history', f.third)).data.calls.length, 0);
  await f.request(`/api/profiles/${id}/actions`, f.owner, { action: 'block', value: true });
  friend.ws.send(JSON.stringify({ type: 'call_signal', roomId: room.id, callSignal: { callId: 'call-two', signalType: 'offer', isVideo: false } }));
  assert.match((await friend.wait(e => e.type === 'error')).reason, /restricted/);
  const group = f.auth.circlesFor(id)[0];
  friend.ws.send(JSON.stringify({ type: 'call_signal', roomId: group.roomId, callSignal: { callId: 'blocked-group-call', signalType: 'offer', targetId: f.owner.user.id, isVideo: false } }));
  assert.match((await friend.wait(e => e.type === 'error')).reason, /restricted/);
  assert.equal((await f.request('/api/calls/history', f.owner)).data.calls.length, 1);
});
test('disappearing messages and their referenced media cannot be read or reacted to after expiry', async t => {
  const f = await fixture(t), id = f.friend.user.id;
  const room = f.auth.directRoom(f.owner.user.id, id);
  f.auth.activateDirectRoom(room.id);
  f.auth.registerRoomMedia(f.owner.user.id, room.id, 'expired.jpg');
  fs.mkdirSync(path.join(f.directory, 'uploads'), { recursive: true });
  fs.writeFileSync(path.join(f.directory, 'uploads', 'expired.jpg'), Buffer.from('test-media'));
  fs.writeFileSync(path.join(f.directory, 'messages.json'), JSON.stringify({ [room.id]: [{ id: 'old', roomId: room.id, senderId: f.owner.user.id, senderName: 'owner', content: '', timestamp: new Date(Date.now() - 2 * 86400000).toISOString(), status: 'sent', mediaAttachment: { id: 'media', fileName: 'expired.jpg', byteSize: 10, mimeType: 'image/jpeg', mediaType: 'image', remoteURL: '/uploads/expired.jpg' } }] }));
  f.profiles.action(f.owner.user.id, id, { action: 'disappearing', seconds: 86400 });
  const restarted = createLoopServer({ dataDirectory: f.directory });
  restarted.server.listen(0, '127.0.0.1'); await once(restarted.server, 'listening');
  t.after(async () => { restarted.wss.close(); restarted.server.closeAllConnections(); await new Promise(resolve => restarted.server.close(resolve)); });
  const base = `http://127.0.0.1:${restarted.server.address().port}`;
  const headers = { Authorization: 'Bearer ' + f.friend.token, 'Content-Type': 'application/json' };
  const card = await (await fetch(base + `/api/profiles/${f.owner.user.id}?roomId=${room.id}`, { headers })).json();
  assert.deepEqual(card.sharedItems, []);
  assert.equal((await fetch(base + '/uploads/expired.jpg', { headers })).status, 404);
  assert.equal((await fetch(base + `/api/chats/${room.id}/messages/old/reaction`, { method: 'POST', headers, body: JSON.stringify({ emoji: '👍' }) })).status, 404);
});

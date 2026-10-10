import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { once } from 'node:events';
import sharp from 'sharp';
import { createLoopServer } from '../dist/server.js';
import { SocialStore } from '../dist/social.js';
const bootstrap = 'social-tests-bootstrap-not-a-live-secret';
async function setup(t) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'loop-social-tests-'));
  let now = Date.now();
  const app = createLoopServer({ dataDirectory: directory, bootstrapKey: bootstrap, now: () => now });
  app.server.listen(0, '127.0.0.1'); await once(app.server, 'listening');
  const base = `http://127.0.0.1:${app.server.address().port}`;
  const input = (secretKey, username) => ({ secretKey, username, chosenDisplayName: username, password: 'test-password-12345' });
  const owner = await app.auth.redeemInvite(input(bootstrap, 'owner'));
  const friend = await app.auth.redeemInvite(input(app.auth.createInvite(owner.user.id, 'circle_main').code, 'friend'));
  t.after(async () => {
    for (const ws of app.wss.clients) ws.terminate(); app.wss.close(); app.server.closeAllConnections();
    await new Promise(resolve => app.server.close(resolve));
    assert.equal(path.dirname(directory), os.tmpdir()); assert.ok(path.basename(directory).startsWith('loop-social-tests-'));
    fs.rmSync(directory, { recursive: true, force: true });
  });
  async function call(route, body, session = owner) {
    const response = await fetch(base + route, { method: body === undefined ? 'GET' : 'POST', headers: { Authorization: 'Bearer ' + session.token, 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) });
    return { status: response.status, data: await response.json() };
  }
  async function upload(session = owner, circleId = 'circle_main') {
    const image = await sharp({ create: { width: 64, height: 40, channels: 3, background: '#3258aa' } }).withExif({ IFD0: { Artist: 'PRIVATE-AUTHOR' } }).jpeg().toBuffer();
    const response = await fetch(base + `/api/circles/${circleId}/social/media`, { method: 'POST', headers: { Authorization: 'Bearer ' + session.token }, body: image });
    assert.equal(response.status, 201); return (await response.json()).fileUrl;
  }
  return { ...app, directory, base, owner, friend, call, upload, advance: ms => { now += ms; } };
}
const prefix = '/api/circles/circle_main/social';
test('social posts persist, never leak across circles, and have account-owned reactions', async t => {
  const app = await setup(t), imageURL = await app.upload();
  const post = await app.call(prefix + '/posts', { imageURL, caption: 'A real post', authorId: 'spoofed' });
  assert.equal(post.status, 201); assert.equal(post.data.author.id, app.owner.user.id);
  assert.equal((await app.call(prefix + `/posts/${post.data.id}/like`, {}, app.friend)).data.likes, 1);
  assert.equal((await app.call(prefix + `/posts/${post.data.id}/like`, {}, app.friend)).data.likes, 0);
  await app.call(prefix + `/posts/${post.data.id}/comments`, { text: 'Hi' }, app.friend);
  const restarted = new SocialStore(app.auth, app.directory, path.join(app.directory, 'uploads'));
  assert.deepEqual(restarted.snapshot(app.friend.user.id, 'circle_main').posts[0].comments, ['Hi']);
  const detail = restarted.snapshot(app.friend.user.id, 'circle_main').posts[0].commentDetails[0];
  assert.equal(detail.author.id, app.friend.user.id);
  assert.equal(detail.author.name, app.auth.socialUser(app.friend.user.id).name);
  assert.equal(detail.text, 'Hi');
  assert.equal(detail.author.passwordHash, undefined);
  assert.equal(detail.author.token, undefined);
  const other = app.auth.createCircle(app.owner.user.id, 'Private');
  assert.equal((await app.call(`/api/circles/${other.id}/social`, undefined, app.friend)).status, 404);
  assert.equal((await app.call(prefix + '/posts', { imageURL }, app.friend)).status, 403);
});
test('story expiry rejects reads and writes; replies are private to the recipient', async t => {
  const app = await setup(t), imageURL = await app.upload();
  const story = (await app.call(prefix + '/stories', { imageURL, caption: 'Today' })).data;
  assert.equal(Date.parse(story.expiresAt) - Date.parse(story.createdAt), 86400000);
  await app.call(prefix + `/stories/${story.id}/replies`, { text: 'Private reply' }, app.friend);
  assert.equal((await app.call(prefix + `/stories/${story.id}/replies`, undefined, app.friend)).status, 404);
  assert.equal((await app.call(prefix + `/stories/${story.id}/replies`)).data.replies[0].text, 'Private reply');
  assert.equal((await app.call(prefix + '/replies', undefined, app.friend)).data.replies.length, 0);
  assert.equal((await app.call(prefix + '/replies')).data.replies.length, 1);
  app.advance(25 * 3600000);
  assert.equal((await app.call(prefix)).data.stories.length, 0);
  assert.equal((await app.call(prefix + `/stories/${story.id}/like`, {}, app.friend)).status, 404);
  assert.equal((await fetch(app.base + imageURL, { headers: { Authorization: 'Bearer ' + app.friend.token } })).status, 404);
});
test('Troll Wall public payload is author-free and opt-out stays enforced after restart', async t => {
  const app = await setup(t), imageURL = await app.upload();
  const posted = await app.call(prefix + '/trolls', { imageURL, caption: 'Funny', subjectIDs: [app.friend.user.id], authorId: 'spoofed' });
  assert.equal(posted.status, 201);
  const troll = posted.data;
  for (const key of ['author', 'authorId', 'moderationAuthorId', 'uploaderId', 'subjects']) assert.equal(troll[key], undefined);
  assert.notEqual(troll.imageURL, imageURL);
  assert.equal((await app.call(prefix + '/posts', { imageURL: troll.imageURL })).status, 403);
  assert.equal((await app.call('/api/auth/profile', { displayName: 'owner', avatarURL: troll.imageURL })).status, 403);
  const internal = JSON.parse(fs.readFileSync(path.join(app.directory, 'social.json')));
  assert.equal(internal.trolls[0].moderationAuthorId, app.owner.user.id);
  await app.call('/api/social/consent', { allowed: false, userID: app.owner.user.id }, app.friend);
  assert.equal(app.auth.socialUser(app.owner.user.id).allowsTrollPosts, true);
  assert.equal((await app.call(prefix)).data.trollPosts.length, 0);
  assert.equal((await app.call(prefix + '/trolls', { imageURL, subjectIDs: [app.friend.user.id] })).status, 403);
  await app.call('/api/social/consent', { allowed: true }, app.friend);
  assert.equal(new SocialStore(app.auth, app.directory, path.join(app.directory, 'uploads')).snapshot(app.owner.user.id, 'circle_main').trollPosts.length, 0);
});
test('reports hide posts for reporter and only owner can moderate', async t => {
  const app = await setup(t), imageURL = await app.upload();
  const troll = (await app.call(prefix + '/trolls', { imageURL, subjectIDs: [app.friend.user.id] })).data;
  await app.call(prefix + `/trolls/${troll.id}/report`, { reason: 'Without permission' }, app.friend);
  assert.equal((await app.call(prefix, undefined, app.friend)).data.trollPosts.length, 0);
  assert.equal((await app.call(prefix)).data.trollPosts.length, 1);
  assert.equal((await app.call(prefix + '/reports', undefined, app.friend)).status, 403);
  const reports = (await app.call(prefix + '/reports')).data.reports;
  assert.equal(reports.length, 1); assert.equal(reports[0].moderationAuthorId, undefined);
  assert.equal((await app.call(prefix + `/trolls/${troll.id}/remove`, {}, app.friend)).status, 403);
  await app.call(prefix + `/trolls/${troll.id}/remove`, {});
  assert.equal((await app.call(prefix)).data.trollPosts.length, 0);
});
test('social photos strip EXIF, reject active input, and cannot be uploaded by outsiders', async t => {
  const app = await setup(t), imageURL = await app.upload();
  const response = await fetch(app.base + imageURL, { headers: { Authorization: 'Bearer ' + app.friend.token } });
  const metadata = await sharp(Buffer.from(await response.arrayBuffer())).metadata();
  assert.equal(metadata.exif, undefined); assert.equal(metadata.format, 'jpeg');
  const invalid = await fetch(app.base + prefix + '/media', { method: 'POST', headers: { Authorization: 'Bearer ' + app.owner.token }, body: '<svg xmlns="http://www.w3.org/2000/svg"/>' });
  assert.equal(invalid.status, 415);
  const privateCircle = app.auth.createCircle(app.owner.user.id, 'Only owner');
  const denied = await fetch(app.base + `/api/circles/${privateCircle.id}/social/media`, { method: 'POST', headers: { Authorization: 'Bearer ' + app.friend.token }, body: 'bad' });
  assert.equal(denied.status, 404);
});
test('post owner actions reject other members and likers remain owner-only', async t => {
  const app = await setup(t);
  const post = (await app.call(prefix + '/posts', { imageURL: await app.upload(), caption: 'Before' })).data;
  const route = prefix + '/posts/' + post.id;
  assert.equal((await app.call(route + '/like', {}, app.friend)).status, 200);
  assert.equal((await app.call(route + '/comments', { text: 'From a friend' }, app.friend)).data.comments[0], 'From a friend');
  assert.equal((await app.call(route + '/likes', undefined, app.friend)).status, 403);
  assert.equal((await app.call(route + '/likes')).data.users[0].id, app.friend.user.id);
  assert.equal((await app.call(route + '/edit', { caption: 'Spoofed' }, app.friend)).status, 403);
  assert.equal((await app.call(route + '/delete', {}, app.friend)).status, 403);
  assert.equal((await app.call(route + '/edit', { caption: 'After' })).data.caption, 'After');
  assert.equal((await app.call(route + '/delete', {})).status, 200);
  assert.equal((await app.call(prefix)).data.posts.length, 0);
  assert.equal((await app.call(route + '/like', {}, app.friend)).status, 404);
});
test('loop names persist for all members and profiles load across shared circles', async t => {
  const app = await setup(t);
  assert.equal((await app.call('/api/circles/circle_main/rename', { name: 'Our renamed loop' }, app.friend)).status, 200);
  assert.equal(app.auth.circlesFor(app.owner.user.id)[0].name, 'Our renamed loop');
  assert.equal((await app.call('/api/circles/circle_main/rename', { name: ' ' })).status, 400);
  const other = app.auth.createCircle(app.owner.user.id, 'Other');
  assert.equal((await app.call(`/api/circles/${other.id}/rename`, { name: 'Forbidden' }, app.friend)).status, 403);
  const file = await app.upload(app.owner, other.id);
  await app.call('/api/auth/profile', { displayName: 'Owner', avatarURL: file });
  assert.equal((await fetch(app.base + file, { headers: { Authorization: 'Bearer ' + app.friend.token } })).status, 200);
  assert.equal((await app.call('/api/circles/circle_main/members', undefined, app.friend)).data.users.find(u => u.id === app.owner.user.id).avatarURL, file);
  assert.equal((await app.call('/api/calls/ice', undefined, app.friend)).status, 200);
  const unauthorized = await fetch(app.base + '/api/calls/ice'); assert.equal(unauthorized.status, 401);
});
import { WebSocket } from 'ws';
async function socket(app, session) {
  const ws = new WebSocket(app.base.replace('http:', 'ws:') + '/ws');
  const messages = []; ws.on('message', data => messages.push(JSON.parse(data)));
  await once(ws, 'open'); ws.send(JSON.stringify({ type: 'auth', token: session.token }));
  async function receive(predicate) {
    const end = Date.now() + 3000;
    while (Date.now() < end) {
      const index = messages.findIndex(predicate);
      if (index >= 0) return messages.splice(index, 1)[0];
      await new Promise(resolve => setTimeout(resolve, 10));
    }
    throw new Error('Expected WebSocket event was not received');
  }
  await receive(m => m.type === 'authenticated');
  return { ws, receive };
}
test('presence, renames, profiles and audio/call payloads synchronize between actual sessions', async t => {
  const app = await setup(t);
  const owner = await socket(app, app.owner), friend = await socket(app, app.friend);
  t.after(() => { owner.ws.terminate(); friend.ws.terminate(); });
  assert.equal((await friend.receive(m => m.type === 'presence_updated' && m.presence.userId === app.owner.user.id)).presence.isOnline, true);
  const renamed = await app.call('/api/circles/circle_main/rename', { name: 'Live loop' }, app.friend);
  assert.equal(renamed.status, 200);
  await owner.receive(m => m.type === 'account_updated');
  const roomId = renamed.data.circle.roomId;
  app.auth.registerMedia(app.friend.user.id, 'circle_main', 'test-voice.m4a');
  friend.ws.send(JSON.stringify({ type: 'send_message', roomId, message: { id: 'voice-note', content: '', mediaAttachment: { fileName: 'voice.m4a', mimeType: 'audio/mp4', byteSize: 1000, mediaType: 'audio', remoteURL: '/uploads/test-voice.m4a', durationSeconds: 12.7 } } }));
  const voice = await owner.receive(m => m.type === 'message_received' && m.message.id === 'voice-note');
  assert.equal(voice.message.mediaAttachment.durationSeconds, 12.7); assert.equal(voice.message.senderId, app.friend.user.id);
  friend.ws.send(JSON.stringify({ type: 'call_signal', roomId, callSignal: { callId: 'test-call', roomId, senderId: 'spoofed', targetId: app.owner.user.id, signalType: 'offer', sdp: 'real-sdp-placeholder-for-contract-only', isVideo: false } }));
  const signal = await owner.receive(m => m.type === 'call_signal'); assert.equal(signal.callSignal.senderId, app.friend.user.id);
  assert.equal(signal.callSignal.targetId, app.owner.user.id);
});
test('private DMs reuse the friend pair, persist, and reject every third-party route', async t => {
  const app = await setup(t);
  const third = await app.auth.redeemInvite({ secretKey: app.auth.createInvite(app.owner.user.id, 'circle_main').code, username: 'third', chosenDisplayName: 'Third', password: 'test-password-12345' });
  const owner = await socket(app, app.owner), friend = await socket(app, app.friend), stranger = await socket(app, third);
  t.after(() => { owner.ws.terminate(); friend.ws.terminate(); stranger.ws.terminate(); });
  const opened = await app.call('/api/chats/direct', { userId: app.friend.user.id });
  assert.equal(opened.status, 200); const room = opened.data.room;
  assert.equal(room.isGroup, false); assert.deepEqual(new Set(room.participantIds), new Set([app.owner.user.id, app.friend.user.id]));
  assert.equal((await app.call('/api/chats/direct', { userId: app.owner.user.id }, app.friend)).data.room.id, room.id);
  assert.equal((await app.call('/api/chats', undefined, app.friend)).data.rooms.some(r => r.id === room.id), true);
  assert.equal((await app.call('/api/chats/direct', { userId: app.owner.user.id })).status, 403);
  assert.equal((await app.call('/api/chats/direct', { userId: 'not-a-friend' })).status, 403);
  assert.equal((await app.call('/api/chats', undefined, third)).data.rooms.some(r => r.id === room.id), false);
  stranger.ws.send(JSON.stringify({ type: 'join_room', roomId: room.id }));
  assert.equal((await stranger.receive(m => m.type === 'error')).reason, 'Room membership required');
  owner.ws.send(JSON.stringify({ type: 'send_message', roomId: room.id, message: { id: 'private-message', content: 'Only two friends' } }));
  assert.equal((await friend.receive(m => m.type === 'message_received' && m.message.id === 'private-message')).message.content, 'Only two friends');
  assert.equal((await app.call('/api/chats', undefined, app.friend)).data.rooms.some(r => r.id === room.id), true);
  const upload = await fetch(app.base + '/api/media/upload', { method: 'POST', headers: { Authorization: 'Bearer ' + app.owner.token, 'X-Room-ID': room.id, 'X-File-Name': 'voice.m4a' }, body: Buffer.from('test-private-media') });
  assert.equal(upload.status, 200); const file = (await upload.json()).fileUrl;
  assert.equal((await fetch(app.base + file, { headers: { Authorization: 'Bearer ' + app.friend.token } })).status, 200);
  assert.equal((await fetch(app.base + file, { headers: { Authorization: 'Bearer ' + third.token } })).status, 404);
  assert.equal((await app.call('/api/auth/profile', { displayName: 'Owner', avatarURL: file })).status, 403);
  stranger.ws.send(JSON.stringify({ type: 'call_signal', roomId: room.id, callSignal: { callId: 'spoof', signalType: 'offer' } }));
  assert.equal((await stranger.receive(m => m.type === 'error')).reason, 'Room membership required');
  const { AuthStore } = await import('../dist/auth.js'); const restarted = new AuthStore(app.directory);
  assert.equal(restarted.directRoom(app.friend.user.id, app.owner.user.id).id, room.id);
  assert.equal(restarted.canAccessRoom(third.user.id, room.id), false);
  assert.equal(restarted.canAccessMedia(third.user.id, path.basename(file)), false);
});
test('a newly created group accepts messages on an already-connected socket', async t => {
  const app = await setup(t), client = await socket(app, app.owner);
  t.after(() => client.ws.terminate());
  const created = await app.call('/api/circles', { name: 'New group' }); assert.equal(created.status, 201);
  const roomId = created.data.circle.roomId;
  await client.receive(m => m.type === 'room_history' && m.roomId === roomId);
  client.ws.send(JSON.stringify({ type: 'send_message', roomId, message: { id: 'new-group-message', content: 'Working now' } }));
  assert.equal((await client.receive(m => m.type === 'message_received' && m.message.id === 'new-group-message')).message.content, 'Working now');
  assert.equal((await app.call('/api/chats')).data.rooms.some(r => r.id === roomId), true);
  assert.equal((await app.call('/api/circles', { name: ' ' })).status, 400);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { once } from 'node:events';
import { createLoopServer } from '../dist/server.js';
import { SpotifyStore } from '../dist/spotify.js';

const clientId = '12345678901234567890123456789012', encryptionKey = 'ab'.repeat(32), redirectURI = 'https://example.test/api/spotify/callback';
const bootstrap = 'spotify-tests-only-bootstrap-key';
const scope = 'user-read-private user-read-playback-state';
const track = overrides => ({ is_playing: true, device: { is_private_session: false }, progress_ms: 45000,
  item: { type: 'track', name: 'Test song', is_local: false, duration_ms: 180000, artists: [{ name: 'Test artist' }], album: { name: 'Test album', images: [{ url: 'https://i.scdn.co/image/test' }] }, external_urls: { spotify: 'https://open.spotify.com/track/test' } }, ...overrides });
async function fixture(t) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'loop-spotify-tests-')); let now = 1800000000000;
  const calls = [], mock = { playback: track(), status: 200, beforePlayer: undefined, beforeProfile: undefined };
  const upstream = async (input, options) => {
    const url = String(input), parameters = options?.body instanceof URLSearchParams ? options.body : undefined;
    calls.push({ url, parameters: parameters ? new URLSearchParams(parameters) : undefined, authorization: options?.headers?.Authorization });
    if (url.endsWith('/api/token')) {
      const id = parameters.get('code') ?? parameters.get('refresh_token').replace('private-refresh-', '').replace('-rotated', '');
      return Response.json({ access_token: 'private-access-' + id, refresh_token: 'private-refresh-' + id + (parameters.get('grant_type') === 'refresh_token' ? '-rotated' : ''), expires_in: 60, scope });
    }
    if (url.endsWith('/v1/me')) {
      if (mock.beforeProfile) await mock.beforeProfile();
      const id = options.headers.Authorization.replace('Bearer private-access-', '');
      return Response.json({ account_id: 'stable-' + id, id: id, display_name: id, external_urls: { spotify: 'https://open.spotify.com/user/' + id } });
    }
    assert.equal(url, 'https://api.spotify.com/v1/me/player');
    if (mock.beforePlayer) await mock.beforePlayer();
    if (mock.status === 204) return new Response(null, { status: 204 });
    return Response.json(mock.playback, { status: mock.status, headers: { 'Retry-After': '60' } });
  };
  const options = { clientId, redirectURI, encryptionKey, fetch: upstream };
  const app = createLoopServer({ dataDirectory: directory, bootstrapKey: bootstrap, now: () => now, spotify: options });
  t.after(() => { app.wss.close(); assert.equal(path.dirname(directory), os.tmpdir()); assert.ok(path.basename(directory).startsWith('loop-spotify-tests-')); fs.rmSync(directory, { recursive: true, force: true }); });
  const redeem = (code, username) => app.auth.redeemInvite({ secretKey: code, username, chosenDisplayName: username, password: 'spotify-test-password-1234' });
  const owner = await redeem(bootstrap, 'owner'), listener = await redeem(app.auth.createInvite(owner.user.id, 'circle_main').code, 'listener');
  const third = await redeem(app.auth.createInvite(owner.user.id, 'circle_main').code, 'third');
  const link = async (session = listener) => {
    const start = app.spotify.begin(session.user.id, session.token);
    const result = await app.spotify.callback(new URLSearchParams({ state: start.attempt, code: session.user.username }));
    assert.equal(new URL(result.redirect).searchParams.get('result'), 'connected'); return start;
  };
  const mutual = () => {
    app.profiles.action(owner.user.id, listener.user.id, { action: 'contact', value: true });
    app.profiles.action(listener.user.id, owner.user.id, { action: 'contact', value: true });
    app.spotify.setSharing(listener.user.id, true);
  };
  return { ...app, directory, owner, listener, third, link, mutual, mock, calls, options, advance: ms => { now += ms; }, now: () => now };
}
test('PKCE is session-bound, single-use, expires, and never exposes or stores plaintext Spotify credentials', async t => {
  const f = await fixture(t), start = await f.link();
  const url = new URL(start.authorizationURL);
  assert.equal(url.searchParams.get('client_id'), clientId); assert.equal(url.searchParams.get('redirect_uri'), redirectURI);
  assert.equal(url.searchParams.get('code_challenge_method'), 'S256'); assert.equal(url.searchParams.get('scope'), scope);
  const exchange = f.calls.find(c => c.url.endsWith('/api/token'));
  assert.equal(url.searchParams.get('code_challenge'), createHash('sha256').update(exchange.parameters.get('code_verifier')).digest('base64url'));
  assert.equal(url.searchParams.has('code_verifier'), false); assert.equal(url.searchParams.has('token'), false);
  await assert.rejects(f.spotify.callback(new URLSearchParams({ state: start.attempt, code: 'listener' })), /expired/);
  await assert.rejects(f.spotify.callback(new URLSearchParams({ state: 'forged', code: 'listener' })), /expired/);
  const saved = fs.readFileSync(path.join(f.directory, 'spotify.json'), 'utf8');
  assert.ok(!saved.includes('private-access')); assert.ok(!saved.includes('private-refresh'));
  const settings = f.spotify.settings(f.listener.user.id); assert.equal(settings.connected, true); assert.equal(settings.sharing, false);
  assert.ok(!JSON.stringify(settings).includes('accessToken'));
  const restarted = new SpotifyStore(f.auth, f.profiles, f.directory, f.options, f.now); assert.equal(restarted.settings(f.listener.user.id).displayName, 'listener');
  assert.throws(() => new SpotifyStore(f.auth, f.profiles, f.directory, { ...f.options, encryptionKey: 'cd'.repeat(32) }), /authenticat/i);
  const expired = f.spotify.begin(f.owner.user.id, f.owner.token); f.advance(600001);
  await assert.rejects(f.spotify.callback(new URLSearchParams({ state: expired.attempt, code: 'owner' })), /expired/);
});
test('activity is opt-in and strictly mutual-contact-only; block and private-profile rules are enforced server-side', async t => {
  const f = await fixture(t); await f.link();
  let value = await f.spotify.presence(f.owner.user.id, f.listener.user.id);
  assert.equal(value.displayName, 'listener'); assert.equal(value.track, undefined); assert.equal(f.calls.filter(c => c.url.endsWith('/player')).length, 0);
  f.spotify.setSharing(f.listener.user.id, true);
  f.profiles.action(f.owner.user.id, f.listener.user.id, { action: 'contact', value: true });
  assert.equal((await f.spotify.presence(f.owner.user.id, f.listener.user.id)).track, undefined);
  f.profiles.action(f.listener.user.id, f.owner.user.id, { action: 'contact', value: true });
  value = await f.spotify.presence(f.owner.user.id, f.listener.user.id); assert.equal(value.track.name, 'Test song'); assert.equal(value.track.artists, 'Test artist');
  assert.ok(!JSON.stringify(value).includes('private-access'));
  assert.equal((await f.spotify.presence(f.third.user.id, f.listener.user.id)).track, undefined);
  f.profiles.action(f.listener.user.id, f.owner.user.id, { action: 'contact', value: false });
  assert.equal((await f.spotify.presence(f.owner.user.id, f.listener.user.id)).track, undefined);
  f.mutual(); f.profiles.action(f.owner.user.id, f.listener.user.id, { action: 'block', value: true });
  assert.deepEqual(await f.spotify.presence(f.owner.user.id, f.listener.user.id), { connected: false });
  f.profiles.action(f.owner.user.id, f.listener.user.id, { action: 'block', value: false });
  f.profiles.edit(f.listener.user.id, { bio: '', pronouns: '', status: '', timeZone: '', private: true, showLocalTime: false, presence: 'everyone', links: [] });
  f.profiles.action(f.listener.user.id, f.owner.user.id, { action: 'contact', value: false });
  assert.deepEqual(await f.spotify.presence(f.owner.user.id, f.listener.user.id), { connected: false });
});
test('polls are deduplicated and paused/private/unknown playback is hidden without returning stale songs', async t => {
  const f = await fixture(t); await f.link(); f.mutual();
  const results = await Promise.all(Array.from({ length: 8 }, () => f.spotify.presence(f.owner.user.id, f.listener.user.id)));
  assert.ok(results.every(r => r.track)); assert.equal(f.calls.filter(c => c.url.endsWith('/player')).length, 1);
  f.mock.playback = track({ is_playing: false }); f.advance(21000);
  assert.equal((await f.spotify.presence(f.owner.user.id, f.listener.user.id)).track, undefined);
  f.mock.playback = track({ device: { is_private_session: true } }); f.advance(21000);
  assert.equal((await f.spotify.presence(f.owner.user.id, f.listener.user.id)).track, undefined);
  f.mock.playback = track({ device: undefined }); f.advance(21000);
  assert.equal((await f.spotify.presence(f.owner.user.id, f.listener.user.id)).track, undefined);
  f.mock.status = 204; f.advance(21000);
  assert.equal((await f.spotify.presence(f.owner.user.id, f.listener.user.id)).track, undefined);
});
test('429 uses a shared cooldown; revoked playback access requests reconnection instead of leaking cached activity', async t => {
  const f = await fixture(t); await f.link(); f.mutual(); f.mock.status = 429;
  assert.equal((await f.spotify.presence(f.owner.user.id, f.listener.user.id)).track, undefined);
  const count = f.calls.length; f.advance(21000);
  assert.equal((await f.spotify.presence(f.owner.user.id, f.listener.user.id)).track, undefined); assert.equal(f.calls.length, count);
  f.mock.status = 200; f.advance(41000); assert.ok((await f.spotify.presence(f.owner.user.id, f.listener.user.id)).track);
  f.mock.status = 401; f.advance(21000);
  assert.equal((await f.spotify.presence(f.owner.user.id, f.listener.user.id)).track, undefined); assert.equal(f.spotify.settings(f.listener.user.id).reconnect, true);
});
test('refresh-token rotation remains encrypted and disconnect survives a restart', async t => {
  const f = await fixture(t); await f.link(); f.mutual(); f.advance(61000);
  assert.ok((await f.spotify.presence(f.owner.user.id, f.listener.user.id)).track);
  const refresh = f.calls.find(c => c.parameters?.get('grant_type') === 'refresh_token'); assert.equal(refresh.parameters.get('refresh_token'), 'private-refresh-listener');
  const saved = fs.readFileSync(path.join(f.directory, 'spotify.json'), 'utf8'); assert.ok(!saved.includes('private-refresh-listener-rotated'));
  f.spotify.disconnect(f.listener.user.id);
  assert.deepEqual(await f.spotify.presence(f.owner.user.id, f.listener.user.id), { connected: false });
  const restarted = new SpotifyStore(f.auth, f.profiles, f.directory, f.options, f.now); assert.equal(restarted.settings(f.listener.user.id).connected, false);
});
test('consent changes and disconnect during a playback request suppress its eventual response', async t => {
  const f = await fixture(t); await f.link(); f.mutual();
  let resolve, entered; const started = new Promise(r => { entered = r; });
  f.mock.beforePlayer = () => { entered(); return new Promise(r => { resolve = r; }); };
  const pending = f.spotify.presence(f.owner.user.id, f.listener.user.id); await started;
  f.spotify.setSharing(f.listener.user.id, false); resolve(); assert.equal((await pending).track, undefined);
  f.mock.beforePlayer = undefined; f.spotify.disconnect(f.listener.user.id);
  assert.deepEqual(await f.spotify.presence(f.owner.user.id, f.listener.user.id), { connected: false });
});
test('cancel/logout cannot finish linking after OAuth network requests have started', async t => {
  const f = await fixture(t); let resolve, entered; const started = new Promise(r => { entered = r; });
  f.mock.beforeProfile = () => { entered(); return new Promise(r => { resolve = r; }); };
  const start = f.spotify.begin(f.listener.user.id, f.listener.token);
  const pending = f.spotify.callback(new URLSearchParams({ state: start.attempt, code: 'listener' })); await started;
  f.spotify.cancel(f.listener.user.id); resolve(); assert.equal(new URL((await pending).redirect).searchParams.get('result'), 'error');
  assert.equal(f.spotify.settings(f.listener.user.id).connected, false);
  f.mock.beforeProfile = undefined;
  const logout = f.spotify.begin(f.listener.user.id, f.listener.token); f.auth.logout(f.listener.token);
  assert.equal(new URL((await f.spotify.callback(new URLSearchParams({ state: logout.attempt, code: 'listener' }))).redirect).searchParams.get('result'), 'error');
});
test('HTTP Spotify endpoints require Loop authentication while the callback safely rejects invalid state', async t => {
  const f = await fixture(t); f.server.listen(0, '127.0.0.1'); await once(f.server, 'listening');
  t.after(async () => { f.server.closeAllConnections(); await new Promise(resolve => f.server.close(resolve)); });
  const base = `http://127.0.0.1:${f.server.address().port}`;
  assert.equal((await fetch(base + '/api/spotify/settings')).status, 401);
  assert.equal((await fetch(base + '/api/spotify/callback?state=forged&code=secret', { redirect: 'manual' })).status, 400);
  const start = await (await fetch(base + '/api/spotify/connect', { method: 'POST', headers: { Authorization: 'Bearer ' + f.owner.token } })).json();
  const callback = await fetch(base + '/api/spotify/callback?' + new URLSearchParams({ state: start.attempt, code: 'owner' }), { redirect: 'manual' });
  assert.equal(callback.status, 302); assert.equal(callback.headers.get('referrer-policy'), 'no-referrer');
  assert.equal(new URL(callback.headers.get('location')).searchParams.get('result'), 'connected');
});

import fs from 'node:fs';
import path from 'node:path';
import { createCipheriv, createDecipheriv, createHash, randomBytes, randomUUID } from 'node:crypto';
import { ApiError, AuthStore } from './auth.js';
import { ProfileStore } from './profiles.js';

export interface SpotifyOptions { clientId?: string; redirectURI?: string; encryptionKey?: string; fetch?: typeof fetch }
interface Account { accountId: string; displayName: string; profileURL: string; accessToken: string; refreshToken: string; expiresAt: number; sharing: boolean; reconnect: boolean; revision: string }
interface Song { name: string; artists: string; album: string; artworkURL?: string; trackURL: string; durationMs: number; progressMs: number; observedAt: string; expiresAt: string }
interface Pending { userId: string; loopToken: string; verifier: string; expiresAt: number; generation: number }
const scopes = ['user-read-private', 'user-read-playback-state'];
function spotifyURL(value: unknown, prefix: string): string | undefined {
  if (typeof value !== 'string' || value.length > 2048) return undefined;
  try { const url = new URL(value); return url.protocol === 'https:' && url.hostname === 'open.spotify.com' && !url.username && !url.password && !url.port && url.pathname.startsWith(prefix) ? url.href : undefined; } catch { return undefined; }
}
/** All OAuth credentials remain on the backend, encrypted at rest. Public responses never contain tokens. */
export class SpotifyStore {
  private accounts: Record<string, Account> = {};
  private pending = new Map<string, Pending>();
  private generations = new Map<string, number>();
  private cache = new Map<string, { checkedAt: number; song?: Song; revision: string }>();
  private inFlight = new Map<string, Promise<Song | undefined>>();
  private backoffUntil = 0;
  private file: string;
  private key?: Buffer;
  private upstream: typeof fetch;
  readonly available: boolean;
  constructor(private auth: AuthStore, private profiles: ProfileStore, directory: string, private options: SpotifyOptions, private now = () => Date.now()) {
    this.file = path.join(directory, 'spotify.json'); this.upstream = options.fetch ?? fetch;
    if (/^[a-fA-F0-9]{64}$/.test(options.encryptionKey ?? '')) this.key = Buffer.from(options.encryptionKey!, 'hex');
    let validRedirect = false;
    try { const url = new URL(options.redirectURI ?? ''); validRedirect = url.protocol === 'https:' && !url.username && !url.password && !url.search && !url.hash && url.pathname === '/api/spotify/callback'; } catch {}
    this.available = /^[a-fA-F0-9]{32}$/.test(options.clientId ?? '') && validRedirect && !!this.key;
    if (fs.existsSync(this.file)) {
      if (!this.key) throw new Error('Spotify encryption key required; refusing to overwrite stored connections');
      const envelope = JSON.parse(fs.readFileSync(this.file, 'utf8'));
      const decipher = createDecipheriv('aes-256-gcm', this.key, Buffer.from(envelope.iv, 'base64'));
      decipher.setAuthTag(Buffer.from(envelope.tag, 'base64'));
      this.accounts = JSON.parse(Buffer.concat([decipher.update(Buffer.from(envelope.data, 'base64')), decipher.final()]).toString('utf8'));
    }
  }
  private save(update: (accounts: Record<string, Account>) => void) {
    if (!this.key) throw new ApiError(503, 'Spotify is not configured on this server.');
    const draft = structuredClone(this.accounts); update(draft);
    const iv = randomBytes(12), cipher = createCipheriv('aes-256-gcm', this.key, iv);
    const data = Buffer.concat([cipher.update(JSON.stringify(draft), 'utf8'), cipher.final()]);
    const temporary = this.file + '.' + randomUUID() + '.tmp';
    try { fs.writeFileSync(temporary, JSON.stringify({ version: 1, iv: iv.toString('base64'), tag: cipher.getAuthTag().toString('base64'), data: data.toString('base64') }), { mode: 0o600, flag: 'wx' }); fs.renameSync(temporary, this.file); this.accounts = draft; }
    finally { if (fs.existsSync(temporary)) fs.unlinkSync(temporary); }
  }
  begin(userId: string, loopToken: string) {
    if (!this.available) throw new ApiError(503, 'Spotify is not configured on this server.');
    this.cancel(userId);
    for (const [state, pending] of this.pending) if (pending.expiresAt <= this.now() || pending.userId === userId) this.pending.delete(state);
    if (this.pending.size >= 1000) throw new ApiError(429, 'Try connecting Spotify later.');
    const state = randomBytes(32).toString('base64url'), verifier = randomBytes(64).toString('base64url');
    this.pending.set(state, { userId, loopToken, verifier, expiresAt: this.now() + 10 * 60000, generation: this.generations.get(userId) ?? 0 });
    const authorization = new URL('https://accounts.spotify.com/authorize');
    authorization.search = new URLSearchParams({ client_id: this.options.clientId!, response_type: 'code', redirect_uri: this.options.redirectURI!, scope: scopes.join(' '), state,
      code_challenge_method: 'S256', code_challenge: createHash('sha256').update(verifier).digest('base64url'), show_dialog: 'true' }).toString();
    return { authorizationURL: authorization.href, attempt: state };
  }
  cancel(userId: string) { this.generations.set(userId, (this.generations.get(userId) ?? 0) + 1); for (const [state, pending] of this.pending) if (pending.userId === userId) this.pending.delete(state); }
  async callback(query: URLSearchParams) {
    const state = query.get('state') ?? '', pending = this.pending.get(state); this.pending.delete(state);
    if (!pending || pending.expiresAt <= this.now()) throw new ApiError(400, 'Spotify connection expired. Start again from Loop.');
    let outcome = 'error';
    try {
      if (this.auth.authenticate(pending.loopToken).id !== pending.userId) throw new Error('Session changed');
      if (query.get('error')) outcome = 'denied';
      else {
        const code = query.get('code'); if (!code || code.length > 2048) throw new Error('Missing code');
        const token = await this.exchange(new URLSearchParams({ grant_type: 'authorization_code', code, redirect_uri: this.options.redirectURI!, code_verifier: pending.verifier }));
        if (!token.refresh_token || !scopes.every(scope => token.scope?.split(' ').includes(scope))) throw new Error('Missing Spotify permissions');
        const response = await this.upstream('https://api.spotify.com/v1/me', { headers: { Authorization: 'Bearer ' + token.access_token }, signal: AbortSignal.timeout(10000), redirect: 'error' });
        if (!response.ok) throw new Error('Spotify profile unavailable');
        const identity = await response.json() as { account_id?: string; id?: string; display_name?: string; external_urls?: { spotify?: string } };
        const accountId = identity.account_id ?? identity.id, profileURL = spotifyURL(identity.external_urls?.spotify, '/user/');
        if (!accountId || typeof accountId !== 'string' || accountId.length > 512 || !profileURL) throw new Error('Invalid Spotify profile');
        // Recheck after network calls: logout/disconnect cancels an in-flight authorization.
        if (this.auth.authenticate(pending.loopToken).id !== pending.userId || this.generations.get(pending.userId) !== pending.generation) throw new Error('Session changed');
        const existing = this.accounts[pending.userId];
        if (Object.entries(this.accounts).some(([id, account]) => id !== pending.userId && account.accountId === accountId)) throw new Error('Spotify is linked to another Loop account');
        this.save(accounts => { accounts[pending.userId] = { accountId, profileURL, displayName: typeof identity.display_name === 'string' ? identity.display_name : 'Spotify user',
          accessToken: token.access_token, refreshToken: token.refresh_token!, expiresAt: this.now() + token.expires_in * 1000, sharing: existing?.accountId === accountId ? existing.sharing : false, reconnect: false, revision: randomUUID() }; });
        this.cache.delete(pending.userId); outcome = 'connected';
      }
    } catch { /* Only an outcome leaves this endpoint; OAuth errors and credentials stay private. */ }
    return { userId: pending.userId, redirect: 'loop-spotify://callback?' + new URLSearchParams({ result: outcome, attempt: state }).toString() };
  }
  private async exchange(parameters: URLSearchParams): Promise<{ access_token: string; refresh_token?: string; expires_in: number; scope?: string }> {
    if (this.now() < this.backoffUntil) throw new ApiError(429, 'Spotify is busy. Try again later.');
    parameters.set('client_id', this.options.clientId!);
    const response = await this.upstream('https://accounts.spotify.com/api/token', { method: 'POST', body: parameters, headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, signal: AbortSignal.timeout(10000), redirect: 'error' });
    if (response.status === 429) this.backoffUntil = this.now() + this.retryDelay(response);
    if (!response.ok) throw new ApiError(response.status, 'Spotify authorization failed. Reconnect your account.');
    const token = await response.json() as { access_token: string; refresh_token?: string; expires_in: number; scope?: string };
    if (typeof token.access_token !== 'string' || !token.access_token || !Number.isFinite(token.expires_in) || token.expires_in <= 0) throw new ApiError(502, 'Spotify returned an invalid token.');
    return token;
  }
  private retryDelay(response: Response) { const seconds = Number(response.headers.get('retry-after') ?? 60); return (Number.isFinite(seconds) ? Math.max(20, Math.min(86400, seconds)) : 60) * 1000; }
  settings(userId: string) {
    const account = this.accounts[userId];
    return { available: this.available, connected: !!account, sharing: account?.sharing ?? false, reconnect: account?.reconnect ?? false,
      displayName: account?.displayName, profileURL: account?.profileURL };
  }
  setSharing(userId: string, value: unknown) {
    if (typeof value !== 'boolean') throw new ApiError(400, 'Invalid Spotify sharing setting.');
    if (!this.accounts[userId]) throw new ApiError(409, 'Connect Spotify first.');
    this.save(accounts => { accounts[userId].sharing = value; }); this.cache.delete(userId);
    return this.settings(userId);
  }
  disconnect(userId: string) { this.cancel(userId); this.save(accounts => { delete accounts[userId]; }); this.cache.delete(userId); return this.settings(userId); }
  private canRead(viewer: string, target: string) {
    if (this.profiles.card(viewer, target).state !== 'active') return false;
    return viewer === target || (!!this.accounts[target]?.sharing && this.profiles.personal(viewer, target).contact && this.profiles.personal(target, viewer).contact && !this.profiles.blocked(viewer, target));
  }
  async presence(viewer: string, target: string) {
    const card = this.profiles.card(viewer, target);
    const account = this.accounts[target];
    if (!account || card.state !== 'active') return { connected: false };
    const song = this.canRead(viewer, target) ? await this.song(target) : undefined;
    // Membership, consent, and connection can change while the upstream request is running.
    const current = this.accounts[target];
    if (!current || current.revision !== account.revision || this.profiles.card(viewer, target).state !== 'active') return { connected: false };
    return { connected: true, displayName: current.displayName, profileURL: current.profileURL, track: this.canRead(viewer, target) ? song : undefined };
  }
  private async song(userId: string): Promise<Song | undefined> {
    const account = this.accounts[userId]; if (!account || account.reconnect || this.now() < this.backoffUntil) return undefined;
    const cached = this.cache.get(userId);
    if (cached?.revision === account.revision && this.now() - cached.checkedAt < 20000) return cached.song && Date.parse(cached.song.expiresAt) > this.now() ? cached.song : undefined;
    const ongoing = this.inFlight.get(userId); if (ongoing) return ongoing;
    const work = this.fetchSong(userId, account); this.inFlight.set(userId, work);
    try { return await work; } finally { this.inFlight.delete(userId); }
  }
  private async fetchSong(userId: string, original: Account): Promise<Song | undefined> {
    let song: Song | undefined;
    try {
      let account = original;
      if (account.expiresAt <= this.now() + 30000) {
        try {
          const token = await this.exchange(new URLSearchParams({ grant_type: 'refresh_token', refresh_token: account.refreshToken }));
          if (this.accounts[userId]?.revision !== original.revision) return undefined;
          this.save(accounts => { const saved = accounts[userId]; saved.accessToken = token.access_token; saved.refreshToken = token.refresh_token ?? saved.refreshToken; saved.expiresAt = this.now() + token.expires_in * 1000; });
          account = this.accounts[userId];
        } catch (error) { if (error instanceof ApiError && [400, 401, 403].includes(error.status)) this.markReconnect(userId, original.revision); throw error; }
      }
      const response = await this.upstream('https://api.spotify.com/v1/me/player', { headers: { Authorization: 'Bearer ' + account.accessToken }, signal: AbortSignal.timeout(10000), redirect: 'error' });
      if (response.status === 429) { this.backoffUntil = this.now() + this.retryDelay(response); this.cache.clear(); return undefined; }
      if ([401, 403].includes(response.status)) { this.markReconnect(userId, original.revision); return undefined; }
      if (response.status === 200) song = this.parseSong(await response.json());
    } catch { song = undefined; }
    if (this.accounts[userId]?.revision !== original.revision) return undefined;
    this.cache.set(userId, { checkedAt: this.now(), song, revision: original.revision }); return song;
  }
  private markReconnect(userId: string, revision: string) { if (this.accounts[userId]?.revision === revision) this.save(accounts => { accounts[userId].reconnect = true; }); this.cache.delete(userId); }
  private parseSong(value: unknown): Song | undefined {
    if (!value || typeof value !== 'object') return undefined;
    const playback = value as { is_playing?: boolean; device?: { is_private_session?: boolean }; item?: { type?: string; name?: string; is_local?: boolean; duration_ms?: number; artists?: { name?: string }[]; album?: { name?: string; images?: { url?: string }[] }; external_urls?: { spotify?: string } }; progress_ms?: number };
    const item = playback.item;
    // Fail closed when Spotify omits the private-session flag; ads, local tracks and podcasts are excluded.
    if (!playback.is_playing || playback.device?.is_private_session !== false || !item || item.type !== 'track' || item.is_local || typeof item.name !== 'string') return undefined;
    const trackURL = spotifyURL(item.external_urls?.spotify, '/track/');
    const artists = item.artists?.filter(a => typeof a.name === 'string').map(a => a.name).join(', ');
    const duration = item.duration_ms, progress = playback.progress_ms;
    if (!trackURL || !artists || !Number.isFinite(duration) || !Number.isFinite(progress) || duration! <= 0 || progress! < 0 || progress! >= duration!) return undefined;
    const artwork = item.album?.images?.find(image => typeof image.url === 'string' && /^https:\/\/i\.scdn\.co\//.test(image.url))?.url;
    return { name: item.name, artists, album: item.album?.name ?? '', artworkURL: artwork, trackURL, durationMs: duration!, progressMs: progress!, observedAt: new Date(this.now()).toISOString(), expiresAt: new Date(this.now() + Math.min(35000, duration! - progress!)).toISOString() };
  }
}

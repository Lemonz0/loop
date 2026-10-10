import { randomBytes, randomUUID, createHash, scrypt, timingSafeEqual } from 'node:crypto';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { AuthSession, UserProfile } from './types.js';

export class ApiError extends Error {
  constructor(public status: number, message: string) { super(message); }
}
interface Account { user: UserProfile; salt: string; passwordHash: string; consentVersion?: number }
interface Circle { createdAt?: string; id: string; name: string; ownerId?: string; memberIds: string[]; roomId: string }
interface Invite { hash: string; circleId: string; expiresAt: number; uses: number; maxUses: number }
interface SessionRecord { hash: string; userId: string; issuedAt: number; expiresAt: number }
interface DirectRoom { id: string; memberIds: string[]; creatorId: string; active: boolean; createdAt: string }
interface State { directRooms?: DirectRoom[]; version: 1; accounts: Account[]; circles: Circle[]; invites: Invite[]; sessions: SessionRecord[]; media: Record<string, string | { circleId?: string; roomId?: string; ownerId: string; social?: boolean; anonymous?: boolean; width?: number; height?: number }> }
const digest = (value: string) => createHash('sha256').update(value).digest('hex');
let passwordWork = 0;
const derive = (password: string, salt: string): Promise<Buffer> => {
  if (passwordWork >= 8) return Promise.reject(new ApiError(429, 'Try again later'));
  passwordWork++;
  return new Promise((resolve, reject) => {
    try {
      scrypt(password, salt, 64, { N: 65536, r: 8, p: 2, maxmem: 96 * 1024 * 1024 }, (error, key) => {
        passwordWork--; error ? reject(error) : resolve(key);
      });
    } catch (error) { passwordWork--; reject(error); }
  });
};
function text(value: unknown, name: string, min: number, max: number): string {
  if (typeof value !== 'string' || value.trim().length < min || value.length > max) throw new ApiError(400, `Invalid ${name}`);
  return value.trim();
}

/** Single-process durable store. Raw passwords, invite codes, and session tokens never persist. */
export class AuthStore {
  private state: State;
  private file: string;
  private dummySalt = randomBytes(16).toString('hex');
  constructor(directory: string, bootstrapKey?: string, private now = () => Date.now()) {
    fs.mkdirSync(directory, { recursive: true });
    this.file = path.join(directory, 'auth.json');
    if (fs.existsSync(this.file)) {
      this.state = JSON.parse(fs.readFileSync(this.file, 'utf8'));
      if (this.state.version !== 1 || !Array.isArray(this.state.accounts) || !Array.isArray(this.state.circles) || !Array.isArray(this.state.sessions) || !Array.isArray(this.state.invites)) throw new Error('Invalid auth store; refusing to overwrite it');
    } else {
      if (!bootstrapKey || (bootstrapKey.length < 24 || bootstrapKey.length > 256)) throw new Error('Set INVITE_KEY to a random secret of at least 24 characters for first startup');
      this.state = { version: 1, accounts: [], circles: [{ id: 'circle_main', name: 'Our Loop', memberIds: [], roomId: randomUUID() }], invites: [{ hash: digest(bootstrapKey), circleId: 'circle_main', expiresAt: this.now() + 7 * 86400000, uses: 0, maxUses: 1 }], sessions: [], media: {} };
      this.commit(() => undefined);
    }
    this.state.directRooms ??= [];
    if (!Array.isArray(this.state.directRooms)) throw new Error("Invalid direct rooms");
  }
  private commit<T>(update: (draft: State) => T): T {
    const draft: State = structuredClone(this.state);
    const result = update(draft);
    const temporary = this.file + '.' + randomUUID() + '.tmp';
    try {
      const fd = fs.openSync(temporary, 'wx', 0o600);
      try { fs.writeFileSync(fd, JSON.stringify(draft)); fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
      fs.renameSync(temporary, this.file);
      this.state = draft;
    } finally { if (fs.existsSync(temporary)) fs.unlinkSync(temporary); }
    return result;
  }
  async redeemInvite(input: Record<string, unknown>): Promise<AuthSession> {
    const code = text(input.secretKey, 'invite', 1, 256);
    const username = text(input.username, 'username', 3, 32).toLowerCase();
    if (!/^[a-z0-9_]+$/.test(username)) throw new ApiError(400, 'Username must use letters, numbers, or underscores');
    const displayName = text(input.chosenDisplayName, 'display name', 1, 60);
    const password = text(input.password, 'password', 12, 128);
    if (password !== input.password) throw new ApiError(400, 'Password must not have leading or trailing whitespace');
    const salt = randomBytes(16).toString('hex');
    const passwordHash = (await derive(password, salt)).toString('hex');
    return this.commit(draft => {
      const invite = draft.invites.find(i => i.hash === digest(code) && i.expiresAt > this.now() && i.uses < i.maxUses);
      if (!invite) throw new ApiError(401, 'Invalid or expired invite');
      if (draft.accounts.some(a => a.user.username === username)) throw new ApiError(409, 'Username is already taken');
      const circle = draft.circles.find(c => c.id === invite.circleId);
      if (!circle) throw new ApiError(401, 'Invalid or expired invite');
      const user = { id: randomUUID(), username, displayName };
      draft.accounts.push({ user, salt, passwordHash });
      circle.memberIds.push(user.id); circle.ownerId ??= user.id; invite.uses++;
      return this.issueSession(draft, user);
    });
  }
  async login(input: Record<string, unknown>): Promise<AuthSession> {
    const username = text(input.username, 'username', 1, 32).toLowerCase();
    const password = typeof input.password === 'string' && input.password.length <= 128 ? input.password : '';
    if (!password) throw new ApiError(401, 'Invalid username or password');
    const account = this.state.accounts.find(a => a.user.username === username);
    const candidate = await derive(password, account?.salt ?? this.dummySalt);
    const expected = account ? Buffer.from(account.passwordHash, 'hex') : Buffer.alloc(64);
    if (!timingSafeEqual(candidate, expected) || !account) throw new ApiError(401, 'Invalid username or password');
    return this.commit(draft => this.issueSession(draft, account.user));
  }
  private issueSession(draft: State, user: UserProfile): AuthSession {
    const token = randomBytes(32).toString('base64url'), issuedAt = this.now(), expiresAt = issuedAt + 30 * 86400000;
    draft.sessions = draft.sessions.filter(s => s.expiresAt > issuedAt);
    draft.sessions.push({ hash: digest(token), userId: user.id, issuedAt, expiresAt });
    return { token, user: { ...user }, issuedAt: new Date(issuedAt).toISOString(), expiresAt: new Date(expiresAt).toISOString() };
  }
  authenticate(token: unknown): UserProfile {
    if (typeof token !== 'string' || token.length > 256) throw new ApiError(401, 'Authentication required');
    const session = this.state.sessions.find(s => s.hash === digest(token) && s.expiresAt > this.now());
    const account = session && this.state.accounts.find(a => a.user.id === session.userId);
    if (!account) throw new ApiError(401, 'Invalid or expired session');
    return { ...account.user };
  }
  updateProfile(userId: string, input: Record<string, unknown>): UserProfile {
    const displayName = text(input.displayName, 'display name', 1, 60);
    if (input.avatarURL !== undefined) {
      if (typeof input.avatarURL !== 'string') throw new ApiError(400, 'Invalid avatar');
      const filename = path.basename(new URL(input.avatarURL, 'http://localhost').pathname);
      const media = this.state.media[filename];
      if (typeof media !== 'string' && media?.anonymous) throw new ApiError(403, 'Anonymous media cannot identify a profile');
      if (typeof media !== 'string' && media?.roomId) throw new ApiError(403, 'Private message media cannot be used as a profile photo');
      if (!this.canAccessMedia(userId, filename)) throw new ApiError(403, 'Avatar must be an authorized upload');
    }
    return this.commit(draft => {
      const account = draft.accounts.find(a => a.user.id === userId)!;
      account.user.displayName = displayName;
      if (input.avatarURL !== undefined) account.user.avatarURL = '/uploads/' + path.basename(new URL(input.avatarURL as string, 'http://localhost').pathname);
      return { ...account.user };
    });
  }
  logout(token: string) { this.commit(draft => { draft.sessions = draft.sessions.filter(s => s.hash !== digest(token)); }); }
  circlesFor(userId: string) { return this.state.circles.filter(c => c.memberIds.includes(userId)).map(c => ({ ...c, memberIds: [...c.memberIds] })); }
  createCircle(userId: string, name: unknown) {
    const circle = { createdAt: new Date(this.now()).toISOString(), id: randomUUID(), name: text(name, 'circle name', 1, 80), ownerId: userId, memberIds: [userId], roomId: randomUUID() };
    return this.commit(draft => { draft.circles.push(circle); return { ...circle }; });
  }
  createInvite(userId: string, circleId: string) {
    const circle = this.state.circles.find(c => c.id === circleId && c.ownerId === userId);
    if (!circle) throw new ApiError(403, 'Only the circle owner can create invites');
    const code = randomBytes(32).toString('base64url'), expiresAt = this.now() + 7 * 86400000;
    this.commit(draft => { draft.invites.push({ hash: digest(code), circleId, expiresAt, uses: 0, maxUses: 1 }); });
    return { code, circleId, expiresAt: new Date(expiresAt).toISOString() };
  }
  renameCircle(userId: string, circleId: string, name: unknown) {
    if (!this.circlesFor(userId).some(c => c.id === circleId)) throw new ApiError(403, 'Circle membership required');
    const cleaned = text(name, 'circle name', 1, 80);
    return this.commit(draft => { const circle = draft.circles.find(c => c.id === circleId)!; circle.name = cleaned; return { ...circle }; });
  }
  joinInvite(userId: string, code: unknown) {
    const hash = digest(text(code, 'invite', 1, 256));
    return this.commit(draft => {
      const invite = draft.invites.find(i => i.hash === hash && i.expiresAt > this.now() && i.uses < i.maxUses);
      if (!invite) throw new ApiError(401, 'Invalid or expired invite');
      const circle = draft.circles.find(c => c.id === invite.circleId)!;
      if (circle.memberIds.includes(userId)) throw new ApiError(409, 'Already a circle member');
      circle.memberIds.push(userId); invite.uses++; return { ...circle };
    });
  }
  directRoom(userId: string, peerId: unknown) {
    if (typeof peerId !== 'string' || peerId === userId || !this.shareCircle(userId, peerId)) throw new ApiError(403, 'Choose a friend in your circle');
    const ids = [userId, peerId].sort();
    let room = this.state.directRooms!.find(r => r.memberIds[0] === ids[0] && r.memberIds[1] === ids[1]);
    if (!room) room = this.commit(draft => {
      const created = { id: randomUUID(), memberIds: ids, creatorId: userId, active: false, createdAt: new Date(this.now()).toISOString() };
      draft.directRooms!.push(created); return created;
    });
    // Opening an existing empty DM is an explicit choice by the second participant.
    if (!room.active && room.creatorId !== userId) this.commit(draft => { draft.directRooms!.find(r => r.id === room!.id)!.active = true; });
    return this.directDTO(room, userId);
  }
  private directDTO(room: DirectRoom, userId: string) {
    const peer = this.socialUser(room.memberIds.find(id => id !== userId)!);
    return { id: room.id, name: peer.name, avatarURL: peer.avatarURL, isGroup: false, participantIds: [...room.memberIds], unreadCount: 0, updatedAt: room.createdAt };
  }
  chatRooms(userId: string) {
    return [...this.circlesFor(userId).map(c => ({ id: c.roomId, name: c.name, isGroup: true, participantIds: c.memberIds, unreadCount: 0, updatedAt: c.createdAt ?? new Date(0).toISOString() })),
      ...this.state.directRooms!.filter(r => r.memberIds.includes(userId) && (r.active || r.creatorId === userId)).map(r => this.directDTO(r, userId))];
  }
  activateDirectRoom(roomId: string) {
    const room = this.state.directRooms!.find(r => r.id === roomId);
    if (room && !room.active) this.commit(draft => { draft.directRooms!.find(r => r.id === roomId)!.active = true; });
  }
  isDirectRoom(roomId: string) { return this.state.directRooms!.some(r => r.id === roomId); }
  registerRoomMedia(userId: string, roomId: string, fileName: string) {
    if (!this.isDirectRoom(roomId) || !this.canAccessRoom(userId, roomId)) throw new ApiError(403, 'Direct room membership required');
    this.commit(draft => { draft.media[fileName] = { roomId, ownerId: userId }; });
  }
  roomsFor(userId: string): string[] { return [...this.circlesFor(userId).map(c => c.roomId), ...this.state.directRooms!.filter(r => r.memberIds.includes(userId)).map(r => r.id)]; }
  canAccessRoom(userId: string, roomId: string): boolean { return this.roomsFor(userId).includes(roomId); }
  shareCircle(first: string, second: string) { return this.state.circles.some(c => c.memberIds.includes(first) && c.memberIds.includes(second)); }
  mediaCircle(fileName: string): string | undefined {
    const media = this.state.media[fileName]; return typeof media === 'string' ? media : media?.circleId;
  }
  socialPhoto(userId: string, circleId: string, fileName: string) {
    const media = this.state.media[fileName];
    if (!media || typeof media === 'string' || media.ownerId !== userId || media.circleId !== circleId || (!media.social || media.anonymous)) throw new ApiError(403, 'Use a photo you uploaded to this circle');
    return { ...media };
  }
  members(userId: string, circleId: string) {
    const circle = this.circlesFor(userId).find(c => c.id === circleId);
    if (!circle) throw new ApiError(404, 'Circle not found');
    return circle.memberIds.map(id => this.socialUser(id));
  }
  socialUser(id: string) {
    const account = this.state.accounts.find(a => a.user.id === id);
    if (!account) throw new ApiError(404, 'User not found');
    return { id, name: account.user.displayName, avatarURL: account.user.avatarURL, allowsTrollPosts: account.user.allowsTrollPosts ?? true };
  }
  consentVersion(id: string) { return this.state.accounts.find(a => a.user.id === id)?.consentVersion ?? 0; }
  setConsent(userId: string, allowed: boolean) {
    this.commit(draft => {
      const account = draft.accounts.find(a => a.user.id === userId)!;
      if (!allowed && (account.user.allowsTrollPosts ?? true)) account.consentVersion = (account.consentVersion ?? 0) + 1;
      account.user.allowsTrollPosts = allowed;
    });
  }
  mediaBelongsToRoom(fileName: string, roomId: string) { const record = this.state.media[fileName]; if (typeof record !== 'string' && record?.roomId) return record.roomId === roomId; return this.state.circles.some(c => c.roomId === roomId && c.id === this.mediaCircle(fileName)); }
  registerMedia(userId: string, circleId: string, fileName: string, photo?: { width: number; height: number; anonymous?: boolean }) {
    if (!this.circlesFor(userId).some(c => c.id === circleId)) throw new ApiError(403, 'Circle membership required');
    this.commit(draft => { draft.media[fileName] = { circleId, ownerId: userId, ...(photo ? { social: true, ...photo } : {}) }; });
  }
  canAccessMedia(userId: string, fileName: string) {
    const media = this.state.media[fileName];
    if (typeof media !== 'string' && media?.roomId) return this.canAccessRoom(userId, media.roomId);
    const circleId = this.mediaCircle(fileName);
    return (!!circleId && this.circlesFor(userId).some(c => c.id === circleId)) ||
      this.state.accounts.some(a => a.user.avatarURL === '/uploads/' + fileName && this.shareCircle(userId, a.user.id));
  }
}
